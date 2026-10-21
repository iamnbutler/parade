import Foundation

/// Fetches AO3 work pages and EPUB exports. No login support (public works only, v1).
public struct AO3Client: Sendable {
    private let session: URLSession
    public static let userAgent = "Parade/1.0 (personal archiving tool; +iamnbutler@gmail.com)"

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
            config.timeoutIntervalForRequest = 30
            self.session = URLSession(configuration: config)
        }
    }

    /// Resolves a link to the list of works it names — one for a work link,
    /// each work in order for a series link.
    public func workIDs(for link: AO3Link) async throws -> [Int] {
        switch link {
        case .work(let id):
            return [id]
        case .series:
            let (html, _) = try await fetchHTML(link.pageURL)
            let ids = HTMLExtract.seriesWorkIDs(in: html)
            guard !ids.isEmpty else { throw AO3Error.parseFailed("no works found in series") }
            return ids
        }
    }

    public func fetchWork(id: Int) async throws -> WorkInfo {
        let url = AO3Link.work(id: id).pageURL
        let (html, response) = try await fetchHTML(url)

        if HTMLExtract.isLoginPage(html, finalURL: response.url) {
            throw AO3Error.restricted
        }
        guard let epubPath = HTMLExtract.epubPath(in: html) else {
            throw AO3Error.parseFailed("EPUB download link")
        }
        guard let title = HTMLExtract.title(in: html) else {
            throw AO3Error.parseFailed("title")
        }
        var authors = HTMLExtract.authors(in: html)
        if authors.isEmpty { authors = ["Anonymous"] }

        guard let epubURL = URL(string: epubPath, relativeTo: URL(string: "https://archiveofourown.org")!)?.absoluteURL else {
            throw AO3Error.parseFailed("EPUB URL")
        }
        let updatedAt = epubPath.components(separatedBy: "updated_at=").dropFirst().first.flatMap { Int($0.prefix(while: \.isNumber)) }

        return WorkInfo(id: id, title: title, authors: authors, epubURL: epubURL, updatedAt: updatedAt)
    }

    /// Downloads the work's EPUB to a temporary file and returns its URL.
    public func downloadEPUB(_ work: WorkInfo) async throws -> URL {
        let (tempURL, response) = try await session.download(for: URLRequest(url: work.epubURL))
        try Self.check(response)
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("epub")
        try FileManager.default.moveItem(at: tempURL, to: dest)
        return dest
    }

    // MARK: - internals

    private func fetchHTML(_ url: URL) async throws -> (String, HTTPURLResponse) {
        let (data, response) = try await session.data(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse else { throw AO3Error.httpError(0) }
        try Self.check(http)
        guard let html = String(data: data, encoding: .utf8) else {
            throw AO3Error.parseFailed("page encoding")
        }
        return (html, http)
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw AO3Error.httpError(0) }
        switch http.statusCode {
        case 200..<300: return
        case 404: throw AO3Error.notFound
        case 429, 503, 525:
            let retryAfter = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(Int.init)
            throw AO3Error.rateLimited(retryAfter: retryAfter)
        default: throw AO3Error.httpError(http.statusCode)
        }
    }
}

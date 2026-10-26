import Foundation

/// Fetches AO3 work pages and EPUB exports. No login support (public works only, v1).
///
/// Every request waits its turn in `scheduler` — there is no way around it.
/// Things the person asked for just now go at `.user` priority (the
/// default); bulk and periodic work at `.background`.
public struct AO3Client: Sendable {
    private let session: URLSession
    public let scheduler: AO3Scheduler
    public static let userAgent = "Parade/1.0 (personal archiving tool; +iamnbutler@gmail.com)"

    public init(session: URLSession? = nil, scheduler: AO3Scheduler = .shared) {
        self.scheduler = scheduler
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
    public func workIDs(for link: AO3Link, priority: AO3Scheduler.Priority = .user) async throws -> [Int] {
        switch link {
        case .work(let id):
            return [id]
        case .series:
            let (html, _) = try await fetchHTML(link.pageURL, priority: priority)
            let ids = HTMLExtract.seriesWorkIDs(in: html)
            guard !ids.isEmpty else { throw AO3Error.parseFailed("no works found in series") }
            return ids
        }
    }

    /// One page of a search or tag listing.
    public func works(_ query: AO3WorkQuery, priority: AO3Scheduler.Priority = .user) async throws -> WorkResults {
        let (html, _) = try await fetchHTML(query.url, priority: priority)
        return BlurbExtract.results(in: html, page: query.page)
    }

    public func fetchWork(id: Int, priority: AO3Scheduler.Priority = .user) async throws -> WorkInfo {
        let url = AO3Link.work(id: id).pageURL
        let (html, response) = try await fetchHTML(url, priority: priority)

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
    public func downloadEPUB(_ work: WorkInfo, priority: AO3Scheduler.Priority = .user) async throws -> URL {
        let session = session
        return try await scheduler.run(priority) {
            let (tempURL, response) = try await session.download(for: URLRequest(url: work.epubURL))
            try Self.check(response)
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("epub")
            try FileManager.default.moveItem(at: tempURL, to: dest)
            return dest
        }
    }

    /// A tag name as AO3 has it: the canonical tag it's a synonym of (or
    /// itself), with its id. `/works?tag_id=` redirects a synonym to its
    /// canonical tag's listing, which names the tag and links its feed by id.
    /// Use `TagResolver`, which asks once per name ever.
    public func resolveTag(_ name: String, priority: AO3Scheduler.Priority = .user) async throws -> TagRef {
        var c = URLComponents(string: "https://archiveofourown.org/works")!
        c.queryItems = [.init(name: "tag_id", value: name)]
        let (html, response) = try await fetchHTML(c.url!, priority: priority)
        let listing = TagExtract.listing(html)
        let landed = response.url
            .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedPath }
            .flatMap(TagExtract.tagName(fromWorksPath:))
        return TagRef(name: name, canonical: listing.name ?? landed ?? name, id: listing.id)
    }

    // MARK: - internals

    private func fetchHTML(_ url: URL, priority: AO3Scheduler.Priority) async throws -> (String, HTTPURLResponse) {
        let session = session
        let (data, http) = try await scheduler.run(priority) { () -> (Data, HTTPURLResponse) in
            let (data, response) = try await session.data(for: URLRequest(url: url))
            guard let http = response as? HTTPURLResponse else { throw AO3Error.httpError(0) }
            try Self.check(http)
            return (data, http)
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw AO3Error.parseFailed("page encoding")
        }
        return (html, http)
    }

    static func check(_ response: URLResponse, now: Date = Date()) throws {
        guard let http = response as? HTTPURLResponse else { throw AO3Error.httpError(0) }
        switch http.statusCode {
        case 200..<300: return
        case 404: throw AO3Error.notFound
        case 429, 503, 525:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After")
                .flatMap { RetryAfter.seconds($0, now: now) }
            throw AO3Error.rateLimited(retryAfter: retryAfter)
        default: throw AO3Error.httpError(http.statusCode)
        }
    }
}

/// The Retry-After header: whole seconds ("120") or an HTTP date
/// ("Sun, 25 Oct 2026 18:30:00 GMT").
public enum RetryAfter {
    /// Seconds to wait from `now`, rounded up; nil if the value is neither form.
    public static func seconds(_ value: String, now: Date = Date()) -> Int? {
        let value = value.trimmingCharacters(in: .whitespaces)
        if let seconds = Int(value) { return max(0, seconds) }
        for format in ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEEE, dd-MMM-yy HH:mm:ss zzz", "EEE MMM d HH:mm:ss yyyy"] {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "GMT")
            f.dateFormat = format
            if let date = f.date(from: value) {
                return max(0, Int(date.timeIntervalSince(now).rounded(.up)))
            }
        }
        return nil
    }
}

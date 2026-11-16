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

    /// The session every client shares by default, so the cookie AO3's
    /// waiting room hands out (your place in line, then your pass) is kept
    /// for all of them.
    static let sharedSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = ["User-Agent": AO3Client.userAgent]
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    public init(session: URLSession? = nil, scheduler: AO3Scheduler = .shared) {
        self.scheduler = scheduler
        self.session = session ?? Self.sharedSession
    }

    /// Resolves a link to the list of works it names — one for a work link,
    /// each work in order for a series link.
    public func workIDs(for link: AO3Link, priority: AO3Scheduler.Priority = .user) async throws -> [Int] {
        switch link {
        case .work(let id), .archivedWork(let id, _, _), .ao3saver(let id, _):
            return [id]
        case .ellipsus:
            throw AO3Error.notAnAO3Link
        case .chapter:
            // AO3 shows the chapter at /chapters/<id> (or redirects it to the
            // work's own address); the page says which work it belongs to.
            let (html, response) = try await fetchHTML(link.pageURL, priority: priority)
            let landed = response.url.flatMap { HTMLExtract.firstMatch(in: $0.path, pattern: #"/works/(\d+)"#) }
                ?? HTMLExtract.workID(inChapterPage: html)
            guard let id = landed.flatMap(Int.init) else { throw AO3Error.notFound }
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
        guard let title = HTMLExtract.title(in: html) else {
            // No work heading at all: not a work page. AO3 serves a plain
            // 200 maintenance or overload page when it's down.
            throw AO3Error.unavailable
        }
        // The EPUB; or, when AO3 has switched EPUB downloads off, its HTML
        // download, which `downloadEPUB` builds into an EPUB. AO3 serves
        // /downloads/<id>/<anything>.<format>, so a page whose links can't
        // be found still has one.
        let epubPath = HTMLExtract.epubPath(in: html)
            ?? HTMLExtract.htmlDownloadPath(in: html)
            ?? "/downloads/\(id)/\(id).html"
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
        if work.epubURL.pathExtension == "html" {
            return try await epubFromHTMLDownload(work, from: work.epubURL, priority: priority)
        }
        do {
            return try await download(work.epubURL, priority: priority)
        } catch let error as AO3Error where Self.isMissingDownload(error) {
            // AO3 turns EPUB downloads off at times (a link that's still on
            // the page may 404 or fail): its HTML download is the same text.
            guard var parts = URLComponents(url: work.epubURL, resolvingAgainstBaseURL: false) else { throw error }
            parts.path = (parts.path as NSString).deletingPathExtension + ".html"
            guard let html = parts.url else { throw error }
            do {
                return try await epubFromHTMLDownload(work, from: html, priority: priority)
            } catch {
                throw error is AO3Error ? error : AO3Error.parseFailed("HTML download")
            }
        }
    }

    /// A downloaded file is only looked into when it isn't a plain success
    /// (or came back as a web page): that's where a waiting room shows.
    static func checkDownload(_ response: URLResponse, file: URL) throws {
        let http = response as? HTTPURLResponse
        let isPage = (http?.value(forHTTPHeaderField: "Content-Type") ?? "").contains("text/html")
        let body = (!(200..<300).contains(http?.statusCode ?? 0) || isPage)
            ? (try? FileHandle(forReadingFrom: file).read(upToCount: 20_000)) : nil
        try check(response, body: body)
    }

    private static func isMissingDownload(_ error: AO3Error) -> Bool {
        switch error {
        case .notFound: return true
        case .httpError(let code): return code >= 400
        default: return false
        }
    }

    private func download(_ url: URL, priority: AO3Scheduler.Priority) async throws -> URL {
        let session = session
        return try await scheduler.run(priority) {
            let (tempURL, response) = try await session.download(for: URLRequest(url: url))
            try Self.checkDownload(response, file: tempURL)
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("epub")
            try FileManager.default.moveItem(at: tempURL, to: dest)
            return dest
        }
    }

    /// AO3's HTML download, read like any AO3 export and written out as an
    /// EPUB laid out as AO3's own is.
    private func epubFromHTMLDownload(_ work: WorkInfo, from url: URL,
                                      priority: AO3Scheduler.Priority) async throws -> URL {
        let session = session
        let data = try await scheduler.run(priority) { () -> Data in
            let (data, response) = try await session.data(for: URLRequest(url: url))
            try Self.check(response, body: data)
            return data
        }
        guard let html = String(data: data, encoding: .utf8) else { throw AO3Error.parseFailed("HTML download encoding") }
        var page = try AO3ExportParser.parse(html, id: work.id)
        // The details a work's own EPUB carries but the export has no field for.
        if page.authors == ["Anonymous"], !work.authors.isEmpty { page.authors = work.authors }
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("epub")
        try WorkPageEPUB.write(page, source: "Built from AO3's HTML download while its EPUB downloads were unavailable.", to: dest)
        return dest
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
            try Self.check(http, body: data)
            return (data, http)
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw AO3Error.parseFailed("page encoding")
        }
        return (html, http)
    }

    /// Cloudflare's Waiting Room page, which AO3 serves (as a 429, or even a
    /// 200) while it lets people in a few at a time.
    static func isWaitingRoom(_ body: Data) -> Bool {
        String(decoding: body.prefix(20_000), as: UTF8.self).contains("Waiting Room powered by Cloudflare")
    }

    static func check(_ response: URLResponse, body: Data? = nil, now: Date = Date()) throws {
        guard let http = response as? HTTPURLResponse else { throw AO3Error.httpError(0) }
        if let body, isWaitingRoom(body) { throw AO3Error.waitingRoom }
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

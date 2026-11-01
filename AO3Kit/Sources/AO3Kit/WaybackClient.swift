import Foundation

/// Saves AO3 works from the Wayback Machine's copies of their pages, for
/// when AO3 is down and people pass around web.archive.org links instead.
///
/// The Wayback Machine almost never has AO3's EPUB export itself, so the
/// EPUB is usually built from the archived page (`WorkPageEPUB`): the same
/// text, tags and preface, in the layout AO3's export uses.
public struct WaybackClient: Sendable {
    /// A queue of its own: the Wayback Machine's limits aren't AO3's, and an
    /// AO3 outage tripping that breaker shouldn't hold these back.
    public static let scheduler = AO3Scheduler()

    private let session: URLSession
    private let scheduler: AO3Scheduler

    public init(session: URLSession? = nil, scheduler: AO3Scheduler = WaybackClient.scheduler) {
        self.scheduler = scheduler
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.httpAdditionalHeaders = ["User-Agent": AO3Client.userAgent]
            config.timeoutIntervalForRequest = 60
            self.session = URLSession(configuration: config)
        }
    }

    public struct ArchivedWork: Sendable {
        public let work: WorkInfo
        public let page: WorkPage
        /// A temporary EPUB file, for `Organizer.place`.
        public let epub: URL
        /// Whether `epub` is AO3's own export the Wayback Machine had,
        /// rather than one built from the page.
        public let isAO3Export: Bool
        /// When the page used was captured.
        public let captured: Date?
    }

    /// The work from the snapshot of `original` nearest `timestamp`; if that
    /// page lacks chapters (a chapter link, or no view_full_work), the
    /// full-work page's snapshot too, if there is one.
    public func fetchWork(id: Int, timestamp: String, original: String,
                          priority: AO3Scheduler.Priority = .user) async throws -> ArchivedWork {
        do {
            let fullWork = "https://archiveofourown.org/works/\(id)?view_adult=true&view_full_work=true"
            var best: (page: WorkPage, captured: String?)?
            var firstError: Error?
            for url in [original, fullWork] {
                if let best, best.page.hasAllChapters { break }
                do {
                    let (html, captured) = try await fetchPage(url, timestamp: timestamp, priority: priority)
                    let page = try WorkPageParser.parse(html, id: id)
                    if best.map({ page.chapters.count > $0.page.chapters.count }) ?? true {
                        best = (page, captured)
                    }
                } catch AO3Error.rateLimited(let retry) {
                    throw AO3Error.rateLimited(retryAfter: retry)
                } catch {
                    firstError = firstError ?? error
                }
            }
            guard let best else {
                if let firstError, firstError as? AO3Error != .notFound { throw firstError }
                throw AO3Error.notArchived
            }
            let page = best.page
            let captured = best.captured.flatMap(Self.date)

            let epubURL = page.epubPath
                .flatMap { URL(string: $0, relativeTo: URL(string: "https://archiveofourown.org")!)?.absoluteURL }
                ?? AO3Link.work(id: id).pageURL
            let updatedAt = page.epubPath?.components(separatedBy: "updated_at=").dropFirst().first
                .flatMap { Int($0.prefix(while: \.isNumber)) }
            let work = WorkInfo(id: id, title: page.title, authors: page.authors, epubURL: epubURL, updatedAt: updatedAt)

            if page.epubPath != nil,
               let export = try? await fetchEPUB(epubURL.absoluteString, timestamp: best.captured ?? timestamp, priority: priority) {
                return ArchivedWork(work: work, page: page, epub: export, isAO3Export: true, captured: captured)
            }
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension("epub")
            let source = "Saved from the Wayback Machine's copy" + (captured.map { " of \(Self.display($0))" } ?? "")
                + " while AO3 was unavailable."
            try WorkPageEPUB.write(page, source: source, to: dest)
            return ArchivedWork(work: work, page: page, epub: dest, isAO3Export: false, captured: captured)
        } catch AO3Error.rateLimited {
            throw AO3Error.archive("The Wayback Machine is rate-limiting requests. Try again in a minute.")
        } catch AO3Error.httpError(let code) {
            throw AO3Error.archive("The Wayback Machine returned HTTP \(code).")
        }
    }

    /// The raw page as captured ("id_": no Wayback toolbar or rewritten
    /// links), and the timestamp of the capture the Wayback Machine chose.
    private func fetchPage(_ original: String, timestamp: String,
                           priority: AO3Scheduler.Priority) async throws -> (String, String?) {
        let url = Self.snapshotURL(original, timestamp: timestamp)
        let session = session
        let (data, response) = try await scheduler.run(priority) { () -> (Data, HTTPURLResponse) in
            let (data, response) = try await session.data(for: URLRequest(url: url))
            guard let http = response as? HTTPURLResponse else { throw AO3Error.httpError(0) }
            try AO3Client.check(http)
            return (data, http)
        }
        guard let html = String(data: data, encoding: .utf8) else { throw AO3Error.parseFailed("page encoding") }
        return (html, response.url.flatMap(Self.timestamp(in:)))
    }

    /// AO3's EPUB export, if the Wayback Machine has it: a temporary file.
    private func fetchEPUB(_ original: String, timestamp: String,
                           priority: AO3Scheduler.Priority) async throws -> URL {
        let url = Self.snapshotURL(original, timestamp: timestamp)
        let session = session
        return try await scheduler.run(priority) {
            let (temp, response) = try await session.download(for: URLRequest(url: url))
            try AO3Client.check(response)
            // A zip, not an HTML error page that came back 200.
            let head = try FileHandle(forReadingFrom: temp).read(upToCount: 2)
            guard head == Data("PK".utf8) else { throw AO3Error.parseFailed("archived EPUB") }
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension("epub")
            try FileManager.default.moveItem(at: temp, to: dest)
            return dest
        }
    }

    static func snapshotURL(_ original: String, timestamp: String) -> URL {
        URL(string: "https://web.archive.org/web/\(timestamp)id_/\(original)")!
    }

    /// "20260828044405" from a snapshot URL.
    static func timestamp(in url: URL) -> String? {
        HTMLExtract.firstMatch(in: url.absoluteString, pattern: #"/web/(\d{14})"#)
    }

    static func date(_ timestamp: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMddHHmmss"
        return f.date(from: timestamp)
    }

    public static func display(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year())
    }
}

import Foundation
import JavaScriptCore

/// Saves stories shared as Ellipsus Reader links (`ellipsus.com/read/<id>`).
/// Ellipsus is a writing app, not an archive: a story is a document with no
/// tags or chapters, so it's saved as one EPUB under its own `ellipsus`
/// provider folder, unlinked from AO3 (an author who also posts there can
/// be linked later).
public struct EllipsusClient: Sendable {
    /// The library folder for Ellipsus stories.
    public static let provider = "ellipsus"

    /// A queue of its own, so an AO3 outage's breaker doesn't hold it back.
    public static let scheduler = AO3Scheduler()

    private let session: URLSession
    private let scheduler: AO3Scheduler

    public init(session: URLSession? = nil, scheduler: AO3Scheduler = EllipsusClient.scheduler) {
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

    public struct SavedWork: Sendable {
        public let work: WorkInfo
        public let page: WorkPage
        /// A temporary EPUB file, for `Organizer.place`.
        public let epub: URL
    }

    struct Resolved: Decodable {
        var name: String?
        var description: String?
        var nickname: String?
        var createdAt: String?
    }

    static func apiURL(_ id: String, _ route: String) -> URL {
        URL(string: "https://service.ellipsus.com/api/reader/link/\(id)/\(route)")!
    }

    public func fetchWork(id: String, priority: AO3Scheduler.Priority = .user) async throws -> SavedWork {
        let resolved: Resolved
        let updates: [String]
        do {
            let info = try await get(Self.apiURL(id, "resolve"), priority: priority)
            resolved = try JSONDecoder().decode(Resolved.self, from: info)
            let body = try await get(Self.apiURL(id, "yjs"), priority: priority)
            updates = try Self.updates(in: body)
        } catch AO3Error.notFound {
            throw AO3Error.archive("Ellipsus has no Reader link \(id). It may have been turned off or the link is wrong.")
        } catch AO3Error.rateLimited {
            throw AO3Error.archive("Ellipsus is rate-limiting requests. Try again in a minute.")
        } catch AO3Error.httpError(let code) where code == 401 || code == 403 {
            throw AO3Error.archive("This Ellipsus story isn't public: its Reader link needs a login.")
        } catch AO3Error.httpError(let code) {
            throw AO3Error.archive("Ellipsus returned HTTP \(code).")
        }

        let page = try Self.page(id: id, resolved: resolved, updates: updates)
        let work = WorkInfo(id: 0, title: page.title, authors: page.authors,
                            epubURL: AO3Link.ellipsus(id: id).pageURL, updatedAt: nil)
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("epub")
        try WorkPageEPUB.write(page, source: "Saved from Ellipsus.", to: dest)
        return SavedWork(work: work, page: page, epub: dest)
    }

    private func get(_ url: URL, priority: AO3Scheduler.Priority) async throws -> Data {
        let session = session
        return try await scheduler.run(priority) { () -> Data in
            let (data, response) = try await session.data(for: URLRequest(url: url))
            try AO3Client.check(response)
            return data
        }
    }

    /// The base64 Yjs updates from the API's `{"updates":[{"data":…}]}`.
    static func updates(in body: Data) throws -> [String] {
        struct Body: Decodable { struct Update: Decodable { var data: String }; var updates: [Update] }
        guard let decoded = try? JSONDecoder().decode(Body.self, from: body) else {
            throw AO3Error.parseFailed("Ellipsus story")
        }
        return decoded.updates.map(\.data)
    }

    static func page(id: String, resolved: Resolved, updates: [String]) throws -> WorkPage {
        guard let title = resolved.name?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            throw AO3Error.parseFailed("Ellipsus story title")
        }
        let (html, words) = try EllipsusDocument.xhtml(updates: updates)
        guard !html.isEmpty else { throw AO3Error.archive("This Ellipsus story has no text yet.") }

        let nickname = resolved.nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var page = WorkPage(id: 0, title: title, authors: [nickname.isEmpty ? "Anonymous" : nickname])
        page.source = .init(name: "Ellipsus", url: AO3Link.ellipsus(id: id).pageURL.absoluteString)
        page.summary = resolved.description.flatMap { text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : XHTMLFragment.make("<p>" + XHTMLFragment.escape(trimmed) + "</p>")
        }
        page.published = resolved.createdAt.map { String($0.prefix(10)) }
        page.words = words.formatted()
        page.chapters = [.init(title: nil, text: html)]
        return page
    }
}

/// An Ellipsus story's document: a Yjs CRDT, rebuilt by Yjs itself running
/// in JavaScriptCore (`Resources/ellipsus-document.js`), then written out as
/// XHTML. Its text is ProseMirror: paragraphs, headings, lists, quotes, and
/// marks (bold, italic…) on runs of text.
enum EllipsusDocument {

    static func xhtml(updates: [String]) throws -> (html: String, words: Int) {
        try xhtml(nodesJSON: try nodesJSON(updates: updates))
    }

    /// The document's top-level nodes as JSON, from the bundled Yjs.
    static func nodesJSON(updates: [String]) throws -> String {
        guard let url = Bundle.module.url(forResource: "ellipsus-document", withExtension: "js"),
              let script = try? String(contentsOf: url, encoding: .utf8),
              let context = JSContext()
        else { throw AO3Error.parseFailed("Ellipsus reader") }
        var failure: String?
        context.exceptionHandler = { _, exception in failure = exception?.toString() }
        context.evaluateScript(script)
        guard let function = context.objectForKeyedSubscript("parseEllipsusDocument"),
              let result = function.call(withArguments: [updates])?.toString(), failure == nil
        else { throw AO3Error.parseFailed(failure ?? "Ellipsus story") }
        return result
    }

    static func xhtml(nodesJSON: String) throws -> (html: String, words: Int) {
        guard let data = nodesJSON.data(using: .utf8),
              let nodes = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { throw AO3Error.parseFailed("Ellipsus story") }
        var words = 0
        var out: [String] = []
        for node in nodes { out.append(block(node, words: &words)) }
        let html = out.filter { !$0.isEmpty }.joined(separator: "\n")
        return (XHTMLFragment.make(html), words)
    }

    private static func block(_ node: [String: Any], words: inout Int) -> String {
        guard let tag = node["tag"] as? String else { return inline(node, words: &words) }
        let attrs = node["attrs"] as? [String: Any] ?? [:]
        let children = node["children"] as? [[String: Any]] ?? []
        func inner() -> String { children.map { block($0, words: &words) }.joined() }

        switch tag {
        case "paragraph":
            let content = inner()
            // An empty paragraph is only spacing.
            guard !content.isEmpty else { return "" }
            return "<p\(align(attrs))>\(content)</p>"
        case "heading":
            let level = min(max((attrs["level"] as? Int) ?? 2, 1), 6)
            return "<h\(level)\(align(attrs))>\(inner())</h\(level)>"
        case "blockquote": return "<blockquote>\(inner())</blockquote>"
        case "bulletList": return "<ul>\(inner())</ul>"
        case "orderedList": return "<ol>\(inner())</ol>"
        case "listItem": return "<li>\(inner())</li>"
        case "horizontalRule": return "<hr/>"
        case "hardBreak": return "<br/>"
        case "codeBlock": return "<pre>\(inner())</pre>"
        default:
            // A node this doesn't know keeps its text, in a block of its own.
            let content = inner()
            return content.isEmpty ? "" : "<div>\(content)</div>"
        }
    }

    private static func align(_ attrs: [String: Any]) -> String {
        guard let value = attrs["textAlign"] as? String, ["center", "right", "justify"].contains(value)
        else { return "" }
        return " style=\"text-align: \(value)\""
    }

    /// A run of text with its marks, outermost first.
    private static func inline(_ node: [String: Any], words: inout Int) -> String {
        let runs = node["text"] as? [[String: Any]] ?? []
        return runs.map { run -> String in
            guard let text = run["insert"] as? String, !text.isEmpty else { return "" }
            words += text.split(whereSeparator: \.isWhitespace).count
            var html = XHTMLFragment.escape(text).replacingOccurrences(of: "\n", with: "<br/>")
            let marks = run["attrs"] as? [String: Any] ?? [:]
            func on(_ key: String) -> Bool { !(marks[key] is NSNull) && marks[key] != nil && (marks[key] as? Bool) != false }
            for (key, tag) in [("code", "code"), ("subscript", "sub"), ("superscript", "sup"), ("strike", "s"),
                               ("underline", "u"), ("italic", "em"), ("bold", "strong")] where on(key) {
                html = "<\(tag)>\(html)</\(tag)>"
            }
            if on("link"), let link = marks["link"] as? [String: Any], let href = link["href"] as? String,
               href.lowercased().hasPrefix("http") {
                html = "<a href=\"\(XHTMLFragment.escape(href))\">\(html)</a>"
            }
            return html
        }.joined()
    }
}

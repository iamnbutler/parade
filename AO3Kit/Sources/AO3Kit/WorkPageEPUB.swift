import Foundation
import ZIPFoundation

/// Builds an EPUB from a `WorkPage`, laid out as AO3's own export is — a
/// preface with the work's link, tags and stats, a file per chapter, an
/// afterword — so the details index, the reader and update checks treat it
/// like any other AO3 download.
public enum WorkPageEPUB {

    /// Writes the EPUB to `url` (replacing nothing: the file must not exist).
    /// `source` is a line for the preface saying where the text came from.
    public static func write(_ page: WorkPage, source: String? = nil, to url: URL) throws {
        let archive = try Archive(url: url, accessMode: .create)
        // The mimetype entry comes first and uncompressed, per the OCF spec.
        try add("mimetype", "application/epub+zip", to: archive, compressed: false)
        for (path, text) in files(page, source: source) {
            try add(path, text, to: archive, compressed: true)
        }
    }

    /// Every file but the mimetype, in order: path → contents. Pure.
    static func files(_ page: WorkPage, source: String? = nil) -> [(String, String)] {
        var documents: [(href: String, title: String?, body: String)] = []
        documents.append(("preface.xhtml", "Preface", preface(page, source: source)))
        for (i, chapter) in page.chapters.enumerated() {
            documents.append(("chapter\(i + 1).xhtml", chapter.title ?? page.title, body(of: chapter)))
        }
        documents.append(("afterword.xhtml", "Afterword", afterword(page)))

        let uid = "ao3-\(page.id)"
        var out: [(String, String)] = [
            ("META-INF/container.xml", container),
            ("content.opf", opf(page, uid: uid, documents: documents.map(\.href))),
            ("toc.ncx", ncx(page, uid: uid, documents: documents.map { ($0.href, $0.title) })),
            ("stylesheet.css", stylesheet),
        ]
        for doc in documents {
            out.append((doc.href, xhtml(title: "\(page.title) - \(page.authors.joined(separator: ", "))",
                                        language: page.language, body: doc.body)))
        }
        return out
    }

    private static func add(_ path: String, _ text: String, to archive: Archive, compressed: Bool) throws {
        let data = Data(text.utf8)
        try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count),
                             compressionMethod: compressed ? .deflate : .none) { position, size in
            data.subdata(in: Int(position)..<Int(position) + size)
        }
    }

    // MARK: - documents

    private static func esc(_ s: String) -> String { XHTMLFragment.escape(s) }

    static func workURL(_ page: WorkPage) -> String { "https://archiveofourown.org/works/\(page.id)" }

    static func preface(_ page: WorkPage, source: String?) -> String {
        let url = workURL(page)
        var s = """
        <div id="preface">
          <h2 class="toc-heading">Preface</h2>
          <p class="message">
            <b>\(esc(page.title))</b><br/>
            Posted originally on the <a href="https://archiveofourown.org/">Archive of Our Own</a> at <a href="\(url)">\(url)</a>.
        """
        if let source { s += "<br/>\n    \(esc(source))" }
        s += "\n  </p>\n  <div>\n    <dl class=\"tags\">\n"

        func pair(_ label: String, _ value: String) {
            s += "      <dt>\(esc(label)):</dt>\n      <dd>\(value)</dd>\n"
        }
        for group in page.tags {
            pair(group.label, group.names.map { name in
                "<a href=\"https://archiveofourown.org/tags/\(tagPath(name))\">\(esc(name))</a>"
            }.joined(separator: ", "))
        }
        if let language = page.language { pair("Language", esc(Locale(identifier: "en").localizedString(forIdentifier: language) ?? language)) }
        if !page.series.isEmpty { pair("Series", page.series.map(esc).joined(separator: ", ")) }
        var stats: [String] = []
        if let p = page.published { stats.append("Published: \(p)") }
        if let l = page.statusLabel, let d = page.statusDate { stats.append("\(l): \(d)") }
        if let w = page.words { stats.append("Words: \(w)") }
        if let c = page.chapterCount { stats.append("Chapters: \(c)") }
        if !stats.isEmpty { pair("Stats", esc(stats.joined(separator: " "))) }
        s += "    </dl>\n  </div>\n</div>\n"

        s += "<div>\n  <h1>\(esc(page.title))</h1>\n"
        let names = page.authorPaths.count == page.authors.count
            ? zip(page.authors, page.authorPaths).map { name, path in
                "<a href=\"https://archiveofourown.org\(esc(path))\" rel=\"author\">\(esc(name))</a>"
            }
            : page.authors.map(esc)
        s += "  <div class=\"byline\">by " + names.joined(separator: ", ") + "</div>\n"
        if let summary = page.summary { s += "  <p>Summary</p>\n  <blockquote class=\"userstuff\">\(summary)</blockquote>\n" }
        if let notes = page.notes { s += "  <p>Notes</p>\n  <blockquote class=\"userstuff\">\(notes)</blockquote>\n" }
        s += "</div>\n"
        return s
    }

    static func body(of chapter: WorkPage.Chapter) -> String {
        var s = "<div id=\"chapters\">\n"
        if let title = chapter.title { s += "  <h2 class=\"heading\">\(esc(title))</h2>\n" }
        if let summary = chapter.summary { s += "  <p>Chapter Summary</p>\n  <blockquote class=\"userstuff\">\(summary)</blockquote>\n" }
        if let notes = chapter.notes { s += "  <p>Chapter Notes</p>\n  <blockquote class=\"userstuff\">\(notes)</blockquote>\n" }
        s += "  <div class=\"userstuff\">\n\(chapter.text)\n  </div>\n"
        if let end = chapter.endNotes { s += "  <p>Chapter End Notes</p>\n  <blockquote class=\"userstuff\">\(end)</blockquote>\n" }
        s += "</div>\n"
        return s
    }

    static func afterword(_ page: WorkPage) -> String {
        var s = "<div id=\"afterword\">\n  <h2 class=\"toc-heading\">Afterword</h2>\n"
        if let end = page.endNotes { s += "  <p>End Notes</p>\n  <blockquote class=\"userstuff\">\(end)</blockquote>\n" }
        s += "  <p class=\"message\">Please <a href=\"\(workURL(page))/comments/new\">drop by the Archive and comment</a> to let the creator know if you enjoyed their work!</p>\n</div>\n"
        return s
    }

    /// AO3's tag URL escaping: "/" → "*s*", "&" → "*a*", then percent-encoding.
    private static func tagPath(_ name: String) -> String {
        let swapped = name.replacingOccurrences(of: "/", with: "*s*").replacingOccurrences(of: "&", with: "*a*")
        return esc(swapped.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? swapped)
    }

    private static func xhtml(title: String, language: String?, body: String) -> String {
        let lang = esc(language ?? "en")
        return """
        <?xml version='1.0' encoding='utf-8'?>
        <html xmlns="http://www.w3.org/1999/xhtml" lang="\(lang)" xml:lang="\(lang)">
          <head>
            <title>\(esc(title))</title>
            <meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
            <link rel="stylesheet" type="text/css" href="stylesheet.css"/>
          </head>
          <body>
        \(body)
          </body>
        </html>

        """
    }

    // MARK: - package

    private static let container = """
    <?xml version="1.0"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles>
        <rootfile full-path="content.opf" media-type="application/oebps-package+xml"/>
      </rootfiles>
    </container>

    """

    private static let stylesheet = """
    blockquote.userstuff { margin: 0.5em 0 1em 1.5em; }
    .byline { margin-bottom: 1em; }
    dt { font-weight: bold; }

    """

    static func opf(_ page: WorkPage, uid: String, documents: [String]) -> String {
        var meta = "    <dc:title>\(esc(page.title))</dc:title>\n"
        meta += "    <dc:language>\(esc(page.language ?? "en"))</dc:language>\n"
        for author in page.authors {
            meta += "    <dc:creator opf:file-as=\"\(esc(author))\" opf:role=\"aut\">\(esc(author))</dc:creator>\n"
        }
        meta += "    <dc:identifier id=\"uid\">\(uid)</dc:identifier>\n"
        if let summary = page.summary { meta += "    <dc:description>\(esc(summary))</dc:description>\n" }
        meta += "    <dc:publisher>Archive of Our Own</dc:publisher>\n"
        meta += "    <dc:source>\(workURL(page))</dc:source>\n"
        for name in page.tags.flatMap(\.names) { meta += "    <dc:subject>\(esc(name))</dc:subject>\n" }
        if let published = page.published { meta += "    <dc:date>\(esc(published))</dc:date>\n" }

        let items = documents.enumerated().map { i, href in
            "    <item id=\"doc\(i)\" href=\"\(href)\" media-type=\"application/xhtml+xml\"/>"
        }.joined(separator: "\n")
        let spine = documents.indices.map { "    <itemref idref=\"doc\($0)\"/>" }.joined(separator: "\n")
        return """
        <?xml version='1.0' encoding='utf-8'?>
        <package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="uid">
          <metadata xmlns:opf="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/">
        \(meta)  </metadata>
          <manifest>
        \(items)
            <item id="css" href="stylesheet.css" media-type="text/css"/>
            <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
          </manifest>
          <spine toc="ncx">
        \(spine)
          </spine>
        </package>

        """
    }

    static func ncx(_ page: WorkPage, uid: String, documents: [(String, String?)]) -> String {
        let points = documents.enumerated().map { i, doc in
            """
                <navPoint id="nav\(i + 1)" playOrder="\(i + 1)">
                  <navLabel><text>\(esc(doc.1 ?? page.title))</text></navLabel>
                  <content src="\(doc.0)"/>
                </navPoint>
            """
        }.joined(separator: "\n")
        return """
        <?xml version='1.0' encoding='utf-8'?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
          <head>
            <meta name="dtb:uid" content="\(uid)"/>
            <meta name="dtb:depth" content="1"/>
            <meta name="dtb:totalPageCount" content="0"/>
            <meta name="dtb:maxPageNumber" content="0"/>
          </head>
          <docTitle><text>\(esc(page.title))</text></docTitle>
          <navMap>
        \(points)
          </navMap>
        </ncx>

        """
    }
}

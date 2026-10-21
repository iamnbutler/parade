import Foundation

/// Narrow, defensive extraction of the handful of fields we need from AO3 pages.
/// AO3's markup has been stable for years; every function here fails soft.
enum HTMLExtract {

    static func title(in html: String) -> String? {
        firstMatch(in: html, pattern: #"<h2 class="title heading">\s*([\s\S]*?)\s*</h2>"#)
            .map(decodeEntities)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    static func authors(in html: String) -> [String] {
        let pattern = #"<a rel="author"[^>]*>([\s\S]*?)</a>"#
        let names = allMatches(in: html, pattern: pattern)
            .map(decodeEntities)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    static func epubPath(in html: String) -> String? {
        firstMatch(in: html, pattern: #"href="(/downloads/[^"]+?\.epub[^"]*)""#)
            .map { $0.replacingOccurrences(of: "&amp;", with: "&") }
    }

    /// Work IDs in series order: the series page lists each work as
    /// `<h4 class="heading"> <a href="/works/NNN">Title</a> ...`.
    static func seriesWorkIDs(in html: String) -> [Int] {
        let pattern = #"<h4 class="heading">\s*<a href="/works/(\d+)""#
        var seen = Set<Int>()
        return allMatches(in: html, pattern: pattern)
            .compactMap(Int.init)
            .filter { seen.insert($0).inserted }
    }

    /// True when AO3 served the login page instead of the work
    /// (restricted works redirect there for logged-out sessions).
    static func isLoginPage(_ html: String, finalURL: URL?) -> Bool {
        if let path = finalURL?.path, path.contains("/users/login") { return true }
        return html.contains(#"id="new_user_session""#)
    }

    // MARK: - helpers

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }

    private static func allMatches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { match in
                guard match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
                return String(text[range])
            }
    }

    /// Decodes the entities AO3 actually emits in titles/names.
    static func decodeEntities(_ s: String) -> String {
        var out = s
        let map = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&#x27;": "'", "&apos;": "'", "&nbsp;": "\u{00A0}"]
        for (entity, char) in map { out = out.replacingOccurrences(of: entity, with: char) }
        // Numeric entities (decimal and hex)
        for pattern in [#"&#(\d+);"#, #"&#x([0-9a-fA-F]+);"#] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let isHex = pattern.contains("x")
            while let match = regex.firstMatch(in: out, range: NSRange(out.startIndex..., in: out)),
                  let full = Range(match.range, in: out),
                  let digits = Range(match.range(at: 1), in: out),
                  let code = UInt32(out[digits], radix: isHex ? 16 : 10),
                  let scalar = Unicode.Scalar(code) {
                out.replaceSubrange(full, with: String(Character(scalar)))
            }
        }
        return out
    }
}

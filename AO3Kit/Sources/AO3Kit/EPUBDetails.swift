import Foundation
import ZIPFoundation

/// Rich metadata read from inside an AO3-exported EPUB — no network, no
/// sidecar files. Works for any AO3 epub regardless of how it reached the
/// library folder.
public struct WorkDetails: Equatable, Sendable {
    public var title: String?
    public var authors: [String] = []
    /// Plain-text summary (AO3 stores it HTML-escaped in dc:description).
    public var summary: String?
    /// The original work page, e.g. https://archiveofourown.org/works/123
    public var workURL: URL?

    public var rating: [String] = []
    public var warnings: [String] = []
    public var categories: [String] = []
    public var fandoms: [String] = []
    public var relationships: [String] = []
    public var characters: [String] = []
    public var additionalTags: [String] = []
    /// e.g. "Part 2 of Some Series"
    public var series: String?

    public var published: String?
    public var updated: String?
    public var words: String?
    public var chapters: String?
}

public extension WorkDetails {
    /// "Part 2 of The Long Series" → "The Long Series"
    var seriesName: String? {
        guard let series else { return nil }
        if let range = series.range(of: #"^Part\s+\d+\s+of\s+"#, options: .regularExpression) {
            return String(series[range.upperBound...])
        }
        return series
    }

    /// "Part 2 of The Long Series" → 2
    var seriesPart: Int? {
        guard let series,
              let range = series.range(of: #"(?<=^Part\s)\s*\d+"#, options: .regularExpression)
        else { return nil }
        return Int(series[range].trimmingCharacters(in: .whitespaces))
    }
}

public enum EPUBDetailsParser {

    /// Reads content.opf and the AO3 preface page out of the EPUB.
    public static func parse(epubAt url: URL) throws -> WorkDetails {
        let archive = try Archive(url: url, accessMode: .read)
        var opf: String?
        var preface: String?
        for entry in archive.sorted(by: { $0.path < $1.path }) {
            let path = entry.path.lowercased()
            if opf == nil, path.hasSuffix(".opf") {
                opf = try? text(of: entry, in: archive)
            } else if preface == nil, path.hasSuffix(".xhtml") || path.hasSuffix(".html") {
                // The preface/title page is the file carrying the tags block.
                if let content = try? text(of: entry, in: archive),
                   content.contains("class=\"tags\"") {
                    preface = content
                }
            }
            if opf != nil, preface != nil { break }
        }
        return parse(opf: opf ?? "", preface: preface)
    }

    private static func text(of entry: Entry, in archive: Archive) throws -> String {
        var data = Data()
        _ = try archive.extract(entry, skipCRC32: true) { data.append($0) }
        guard let s = String(data: data, encoding: .utf8) else {
            throw AO3Error.parseFailed("epub entry encoding")
        }
        return s
    }

    /// Pure string parsing — testable without zip files.
    static func parse(opf: String, preface: String?) -> WorkDetails {
        var d = WorkDetails()

        d.title = firstMatch(in: opf, pattern: #"<dc:title>([\s\S]*?)</dc:title>"#)
            .map(HTMLExtract.decodeEntities)
        d.authors = allMatches(in: opf, pattern: #"<dc:creator[^>]*>([\s\S]*?)</dc:creator>"#)
            .map(HTMLExtract.decodeEntities)
        if let raw = firstMatch(in: opf, pattern: #"<dc:description>([\s\S]*?)</dc:description>"#) {
            // dc:description holds escaped HTML: decode, then strip tags.
            let html = HTMLExtract.decodeEntities(raw)
            let text = html
                .replacingOccurrences(of: #"</p>\s*<p[^>]*>"#, with: "\n\n", options: .regularExpression)
                .replacingOccurrences(of: #"<br[^>]*>"#, with: "\n", options: .regularExpression)
                .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            d.summary = text.isEmpty ? nil : HTMLExtract.decodeEntities(text)
        }

        guard let preface else { return d }

        if let urlString = firstMatch(
            in: preface, pattern: #"<a href="(https?://archiveofourown\.org/works/\d+)">"#) {
            d.workURL = URL(string: urlString)
        }

        // The tags block is dt/dd pairs: label → comma-separated tag links.
        let pairPattern = #"<dt[^>]*>\s*([^<]+?):\s*</dt>\s*<dd[^>]*>([\s\S]*?)</dd>"#
        guard let regex = try? NSRegularExpression(pattern: pairPattern) else { return d }
        let range = NSRange(preface.startIndex..., in: preface)
        for match in regex.matches(in: preface, range: range) {
            guard let labelRange = Range(match.range(at: 1), in: preface),
                  let valueRange = Range(match.range(at: 2), in: preface) else { continue }
            let label = String(preface[labelRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(preface[valueRange])
            apply(label: label, value: value, to: &d)
        }
        return d
    }

    private static func apply(label: String, value: String, to d: inout WorkDetails) {
        switch label.lowercased() {
        case let l where l.hasPrefix("rating"): d.rating = tagNames(in: value)
        case let l where l.hasPrefix("archive warning"): d.warnings = tagNames(in: value)
        case let l where l.hasPrefix("categor"): d.categories = tagNames(in: value)
        case let l where l.hasPrefix("fandom"): d.fandoms = tagNames(in: value)
        case let l where l.hasPrefix("relationship"): d.relationships = tagNames(in: value)
        case let l where l.hasPrefix("character"): d.characters = tagNames(in: value)
        case let l where l.hasPrefix("additional tag"): d.additionalTags = tagNames(in: value)
        case let l where l.hasPrefix("series"):
            let text = plainText(value)
            d.series = text.isEmpty ? nil : text
        case let l where l.hasPrefix("stats"):
            let text = plainText(value)
            d.published = firstMatch(in: text, pattern: #"Published:\s*(\S+)"#)
            d.updated = firstMatch(in: text, pattern: #"(?:Updated|Completed):\s*(\S+)"#)
            d.words = firstMatch(in: text, pattern: #"Words:\s*([\d,]+)"#)
            d.chapters = firstMatch(in: text, pattern: #"Chapters:\s*(\S+)"#)
        default: break
        }
    }

    /// Tag links → their display names; falls back to the plain text.
    private static func tagNames(in html: String) -> [String] {
        let names = allMatches(in: html, pattern: #"<a [^>]*>([\s\S]*?)</a>"#)
            .map { HTMLExtract.decodeEntities($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !names.isEmpty { return names }
        let text = plainText(html)
        return text.isEmpty ? [] : text.components(separatedBy: ", ")
    }

    private static func plainText(_ html: String) -> String {
        HTMLExtract.decodeEntities(
            html.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
}

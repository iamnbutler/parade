import Foundation

/// A parsed AO3 link — a single work, a series, or a Wayback Machine
/// snapshot of a work's page (for when AO3 itself is down).
public enum AO3Link: Equatable, Sendable {
    case work(id: Int)
    case series(id: Int)
    /// `https://web.archive.org/web/<timestamp>/<original>`, where
    /// `original` is an AO3 work URL (scheme included, fragment dropped).
    case archivedWork(id: Int, timestamp: String, original: String)

    /// Extracts the first AO3 work or series link found in `text`.
    /// Accepts archiveofourown.org URLs (chapter links, collection-scoped
    /// links, query params, missing scheme), Wayback Machine snapshots of
    /// work pages, or a bare "/works/12345" path.
    public init?(text: String) {
        if let archived = Self.archived(in: text) {
            self = archived
            return
        }
        // A real AO3 URL anywhere in the text, or the string itself is just a path.
        let patterns = [
            #"archiveofourown\.org/(?:collections/[^/\s]+/)?(works|series)/(\d+)"#,
            #"^\s*/?(works|series)/(\d+)"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let kindRange = Range(match.range(at: 1), in: text),
                  let idRange = Range(match.range(at: 2), in: text),
                  let id = Int(text[idRange])
            else { continue }
            switch text[kindRange] {
            case "works": self = .work(id: id)
            case "series": self = .series(id: id)
            default: continue
            }
            return
        }
        return nil
    }

    /// Every distinct AO3 work or series link in `text`, in order — for
    /// pasting a batch of links at once (one per line, comma-separated, or
    /// buried in a block of text).
    public static func all(in text: String) -> [AO3Link] {
        var links: [AO3Link] = []
        // Split on whitespace and commas so bare "/works/1" paths on their
        // own line are found too, not only full URLs.
        let pieces = text.split(whereSeparator: { $0.isWhitespace || $0 == "," })
        for piece in pieces {
            guard let link = AO3Link(text: String(piece)), !links.contains(link) else { continue }
            links.append(link)
        }
        return links
    }

    /// The AO3 work this link names, if it names one work.
    public var workID: Int? {
        switch self {
        case .work(let id), .archivedWork(let id, _, _): return id
        case .series: return nil
        }
    }

    /// A Wayback Machine link to an AO3 work page, with any capture
    /// modifier ("id_", "if_") on the timestamp. Archived series pages
    /// aren't handled: their works' own pages are rarely captured.
    private static func archived(in text: String) -> AO3Link? {
        let pattern = #"web\.archive\.org/web/(\d{4,14})(?:[a-z]{2}_)?/((?:https?://)?(?:www\.)?archiveofourown\.org/(?:collections/[^/\s]+/)?works/(\d+)[^\s#]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let stampRange = Range(match.range(at: 1), in: text),
              let originalRange = Range(match.range(at: 2), in: text),
              let idRange = Range(match.range(at: 3), in: text),
              let id = Int(text[idRange])
        else { return nil }
        var original = String(text[originalRange])
        if !original.lowercased().hasPrefix("http") { original = "https://" + original }
        return .archivedWork(id: id, timestamp: String(text[stampRange]), original: original)
    }

    public var pageURL: URL {
        switch self {
        case .work(let id), .archivedWork(let id, _, _):
            return URL(string: "https://archiveofourown.org/works/\(id)?view_adult=true")!
        case .series(let id):
            return URL(string: "https://archiveofourown.org/series/\(id)?view_adult=true")!
        }
    }
}

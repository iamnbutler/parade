import Foundation

/// A parsed AO3 link — either a single work or a series.
public enum AO3Link: Equatable, Sendable {
    case work(id: Int)
    case series(id: Int)

    /// Extracts the first AO3 work or series link found in `text`.
    /// Accepts archiveofourown.org URLs (chapter links, collection-scoped
    /// links, query params, missing scheme) or a bare "/works/12345" path.
    public init?(text: String) {
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

    public var pageURL: URL {
        switch self {
        case .work(let id):
            return URL(string: "https://archiveofourown.org/works/\(id)?view_adult=true")!
        case .series(let id):
            return URL(string: "https://archiveofourown.org/series/\(id)?view_adult=true")!
        }
    }
}

import Foundation

/// Metadata scraped from an AO3 work page.
public struct WorkInfo: Equatable, Sendable, Codable {
    public let id: Int
    public let title: String
    public let authors: [String]
    /// Absolute URL of AO3's own EPUB export for this work.
    public let epubURL: URL
    /// AO3's updated_at stamp from the download URL, if present.
    /// Changes when the work is edited — useful for update detection.
    public let updatedAt: Int?
    /// Chapters posted, as the work page's stats say ("19" of "19/20");
    /// nil when it wasn't read from AO3's own page.
    public var postedChapters: Int?

    public init(id: Int, title: String, authors: [String], epubURL: URL, updatedAt: Int?,
                postedChapters: Int? = nil) {
        self.id = id
        self.title = title
        self.authors = authors
        self.epubURL = epubURL
        self.updatedAt = updatedAt
        self.postedChapters = postedChapters
    }

    /// "Author" or "Author & Other" — display/folder form.
    public var authorLabel: String {
        authors.isEmpty ? "Anonymous" : authors.joined(separator: " & ")
    }
}

public enum AO3Error: Error, LocalizedError, Equatable {
    case notAnAO3Link
    case notFound
    /// Work is restricted to logged-in users; AO3 bounced us to the login page.
    case restricted
    /// AO3 asked us to slow down. Retry after the given number of seconds, if known.
    case rateLimited(retryAfter: Int?)
    case parseFailed(String)
    case httpError(Int)
    /// The Wayback Machine has no capture of the page asked for.
    case notArchived
    /// Something else went wrong fetching from the Wayback Machine.
    case archive(String)
    /// AO3 answered, but not with the work's page — a maintenance or
    /// overload page, which is what it serves when it's down.
    case unavailable
    /// AO3 is letting people in through a Cloudflare Waiting Room, a queue,
    /// and this request is still in it.
    case waitingRoom
    /// A download had fewer chapters than it should: `expected` is the
    /// work's stated count or the saved copy's, whichever is more. With
    /// `keptSaved`, a saved copy was there and was left as it was.
    case missingChapters(got: Int, expected: Int, keptSaved: Bool)

    public var errorDescription: String? {
        switch self {
        case .notAnAO3Link: return "That doesn't look like an AO3 work or series link."
        case .notFound: return "AO3 returned 404 — the work may be deleted or the link is wrong."
        case .restricted: return "This work is restricted to logged-in AO3 users."
        case .rateLimited(let secs):
            let hint = secs.map { " Try again in \($0)s." } ?? " Try again in a minute."
            return "AO3 is rate-limiting requests." + hint
        case .parseFailed(let what): return "Couldn't read the AO3 page (\(what)). The site layout may have changed."
        case .httpError(let code): return "AO3 returned HTTP \(code)."
        case .notArchived: return "The Wayback Machine has no copy of this work's page."
        case .archive(let message): return message
        case .waitingRoom:
            return "AO3 has a waiting room up while it recovers, and you're still in line. Parade keeps your place; try again in a few minutes."
        case .missingChapters(let got, let expected, let keptSaved):
            let what = "The download had only \(got) of \(expected) chapter\(expected == 1 ? "" : "s")"
            return keptSaved
                ? what + ", so Parade kept the copy you already had. Try again later."
                : what + ", so Parade didn't save it. Try again later."
        case .unavailable:
            return "AO3 isn't serving work pages right now (it may be down or overloaded). Try again later, or paste an ao3saver.com or Wayback Machine link."
        }
    }
}

public extension AO3Error {
    /// Whether this means AO3 itself isn't serving the work — down, busy or
    /// failing — so a saved copy elsewhere is worth trying. A deleted or
    /// restricted work isn't: those copies wouldn't be there either.
    var suggestsAO3IsDown: Bool {
        switch self {
        case .unavailable, .rateLimited, .waitingRoom: return true
        case .httpError(let code): return code >= 500
        case .parseFailed(let what): return what == "EPUB download link" || what == "title" || what == "HTML download"
        default: return false
        }
    }
}

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

    public init(id: Int, title: String, authors: [String], epubURL: URL, updatedAt: Int?) {
        self.id = id
        self.title = title
        self.authors = authors
        self.epubURL = epubURL
        self.updatedAt = updatedAt
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
        }
    }
}

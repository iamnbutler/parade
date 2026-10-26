import Foundation

/// Finds which of many works have been updated, a few search pages at a
/// time instead of one request per work.
///
/// The IDs go into AO3's work search as `id:1 OR id:2 OR …` (at most
/// `AO3WorkQuery.maxIDs` per query), narrowed to works revised since the
/// last check and sorted by update date. Each result page lists 20 works
/// with their chapter counts and last-updated day. Every page is one
/// request through the scheduler at background priority, so it rests
/// between batches and gives way to anything the person does.
public struct AO3UpdateCheck: Sendable {
    /// How the "revised since" filter is sent.
    public enum DateFilter: Sendable {
        /// `work_search[revised_at]=< N days`. Verified against AO3; preferred.
        case field
        /// `(id:… OR …) AND revised_at:[day TO *]` in the query text.
        case inQuery
    }

    /// Since dates are pushed back this far: AO3 shows update days, not times.
    public static let overlap: TimeInterval = 24 * 60 * 60

    public var dateFilter: DateFilter
    private let fetch: @Sendable (AO3WorkQuery) async throws -> WorkResults
    private let now: @Sendable () -> Date

    public init(client: AO3Client = AO3Client(), dateFilter: DateFilter = .field,
                priority: AO3Scheduler.Priority = .background) {
        self.init(dateFilter: dateFilter) { try await client.works($0, priority: priority) }
    }

    init(dateFilter: DateFilter = .field,
         now: @escaping @Sendable () -> Date = { Date() },
         fetch: @escaping @Sendable (AO3WorkQuery) async throws -> WorkResults) {
        self.dateFilter = dateFilter
        self.now = now
        self.fetch = fetch
    }

    /// The works among `ids` revised since `since` (all of them when nil),
    /// a page of blurbs at a time. Each blurb carries `chaptersPosted`,
    /// `chaptersExpected` and `updated`. Works AO3 no longer lists (deleted,
    /// or restricted to logged-in users) simply don't appear.
    ///
    /// Throws `AO3Error.rateLimited` only once the scheduler has given up
    /// retrying. Cancel by cancelling the consuming task.
    public func revisedWorks(ids: [Int], since: Date?) -> AsyncThrowingStream<[WorkBlurb], Error> {
        let queries = Self.queries(ids: ids, since: since, now: now(), dateFilter: dateFilter)
        let fetch = fetch
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for first in queries {
                        var query = first
                        // A chunk can't list more works than it named.
                        let maxPages = Self.maxPages(for: first)
                        while true {
                            try Task.checkCancellation()
                            let results = try await fetch(query)
                            if !results.works.isEmpty { continuation.yield(results.works) }
                            guard results.hasNextPage, !results.works.isEmpty, query.page < maxPages else { break }
                            query.page += 1
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Page 1 of each search: IDs deduplicated and chunked, newest updates first.
    public static func queries(ids: [Int], since: Date?, now: Date = Date(),
                               dateFilter: DateFilter = .field) -> [AO3WorkQuery] {
        var seen = Set<Int>()
        let unique = ids.filter { seen.insert($0).inserted }
        let revised: AO3WorkQuery.RevisedFilter? = since.map { since in
            let from = since.addingTimeInterval(-overlap)
            switch dateFilter {
            case .field:
                let days = Int((now.timeIntervalSince(from) / overlap).rounded(.up))
                return .withinDays(max(1, days))
            case .inQuery:
                return .inQuery(since: from)
            }
        }
        return stride(from: 0, to: unique.count, by: AO3WorkQuery.maxIDs).map { start in
            let chunk = Array(unique[start..<min(start + AO3WorkQuery.maxIDs, unique.count)])
            return AO3WorkQuery(source: .ids(chunk), sort: .updated, revised: revised)
        }
    }

    static func maxPages(for query: AO3WorkQuery) -> Int {
        guard case .ids(let ids) = query.source else { return 1 }
        return max(1, (ids.count + 19) / 20)
    }
}

extension AO3Client {
    /// `AO3UpdateCheck` through this client at background priority.
    public func revisedWorks(ids: [Int], since: Date?) -> AsyncThrowingStream<[WorkBlurb], Error> {
        AO3UpdateCheck(client: self).revisedWorks(ids: ids, since: since)
    }
}

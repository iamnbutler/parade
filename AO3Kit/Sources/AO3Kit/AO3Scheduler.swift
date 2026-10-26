import Foundation

/// The one gate every AO3 request passes through. AO3 is run by volunteers
/// and asks that it not be hammered, so requests go one at a time, a few
/// seconds apart, and back off hard when the site says to slow down.
///
/// - One request in flight; the next starts no sooner than `spacing` (±20%)
///   after the last one finished.
/// - `.user` requests always go ahead of `.background` ones.
/// - Background work rests after every `batchSize` requests.
/// - A rate-limit response (429/503/525) makes every request wait
///   max(Retry-After, base·2ⁿ) ±30%, capped, then the request is retried.
/// - Too many rate limits in a short window pause everything for a while,
///   longer each time it trips again before a request succeeds.
public actor AO3Scheduler {
    public enum Priority: Int, Sendable, Comparable {
        case background
        case user

        public static func < (a: Priority, b: Priority) -> Bool { a.rawValue < b.rawValue }
    }

    /// What the scheduler is doing, for the UI to show.
    public enum State: Sendable, Equatable {
        /// Nothing queued or in flight.
        case idle
        /// A request is in flight or about to start.
        case running
        /// Holding off — after a rate limit, or resting between batches.
        case waiting(until: Date)
        /// The circuit breaker tripped; nothing goes out until then.
        case paused(until: Date)
    }

    public struct Configuration: Sendable {
        /// Gap between the end of one request and the start of the next.
        public var spacing: TimeInterval = 3
        public var spacingJitter: Double = 0.2
        /// First back-off after a rate limit; doubles with each one in a row.
        public var backoffBase: TimeInterval = 20
        public var backoffJitter: Double = 0.3
        public var maxBackoff: TimeInterval = 15 * 60
        /// Tries per request, the first included, before a rate limit is thrown.
        public var maxAttempts = 5
        /// This many rate limits within `breakerWindow` pause everything.
        public var breakerThreshold = 3
        public var breakerWindow: TimeInterval = 5 * 60
        /// The first pause; doubles each time the breaker trips again
        /// before a request succeeds.
        public var breakerPause: TimeInterval = 10 * 60
        /// Background requests between rests.
        public var batchSize = 20
        public var batchRest: TimeInterval = 60

        public init() {}
    }

    /// The scheduler the app's AO3 requests share.
    public static let shared = AO3Scheduler()

    public nonisolated let configuration: Configuration
    private let clock: any AO3Clock
    private let random: @Sendable (ClosedRange<Double>) -> Double

    public init(
        configuration: Configuration = Configuration(),
        clock: any AO3Clock = SystemClock(),
        random: @escaping @Sendable (ClosedRange<Double>) -> Double = { Double.random(in: $0) }
    ) {
        self.configuration = configuration
        self.clock = clock
        self.random = random
    }

    // MARK: - state

    public private(set) var state: State = .idle {
        didSet { if state != oldValue { for c in observers.values { c.yield(state) } } }
    }
    private var observers: [UUID: AsyncStream<State>.Continuation] = [:]

    /// The current state, then every change to it.
    public func stateUpdates() -> AsyncStream<State> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<State>.makeStream()
        continuation.yield(state)
        observers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        return stream
    }

    private func removeObserver(_ id: UUID) { observers[id] = nil }

    // MARK: - queue

    private struct Ticket {
        let id: Int
        let priority: Priority
    }

    private var queue: [Ticket] = []
    private var nextTicket = 0
    private var busy = false
    private var wakers: [Int: CheckedContinuation<Void, Error>] = [:]
    private var cancelledTickets: Set<Int> = []

    /// No request starts before this: spacing, or a rate-limit back-off.
    private var notBefore = Date.distantPast
    private var backingOff = false
    private var pausedUntil = Date.distantPast
    /// Background requests since the last rest.
    private var batchCount = 0
    private var lastFinish = Date.distantPast

    private var recentLimits: [Date] = []
    private var consecutiveLimits = 0
    private var breakerTrips = 0

    /// Requests waiting their turn (not counting one in flight).
    var pendingCount: Int { queue.count }

    /// Runs `operation` when its turn comes. A rate-limit error from it
    /// (`AO3Error.rateLimited`) holds back every request and retries this one;
    /// after `maxAttempts` the error is rethrown. Cancelling the calling task
    /// takes it out of the queue.
    public func run<T: Sendable>(
        _ priority: Priority = .user,
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        let ticket = Ticket(id: nextTicket, priority: priority)
        nextTicket += 1
        var attempt = 0
        while true {
            attempt += 1
            try await takeTurn(ticket)
            do {
                let value = try await operation()
                finish(ticket, rateLimit: nil)
                return value
            } catch AO3Error.rateLimited(let retryAfter) {
                let retrying = attempt < configuration.maxAttempts
                finish(ticket, rateLimit: retryAfter.map(TimeInterval.init) ?? 0, retrying: retrying)
                if !retrying { throw AO3Error.rateLimited(retryAfter: retryAfter) }
            } catch {
                finish(ticket, rateLimit: nil, failed: true)
                throw error
            }
        }
    }

    /// Waits until `ticket` is first in line, nothing is in flight, and
    /// every hold (pause, back-off, spacing, batch rest) has passed.
    private func takeTurn(_ ticket: Ticket) async throws {
        insert(ticket)
        do {
            while true {
                try Task.checkCancellation()
                guard !busy, queue.first?.id == ticket.id else {
                    try await waitForSignal(ticket.id)
                    continue
                }
                let now = clock.now
                let ready = readyTime(for: ticket.priority, now: now)
                if ready <= now {
                    queue.removeFirst()
                    busy = true
                    if ticket.priority == .background {
                        if now.timeIntervalSince(lastFinish) >= configuration.batchRest { batchCount = 0 }
                        batchCount += 1
                    }
                    state = .running
                    return
                }
                state = pausedUntil > now ? .paused(until: pausedUntil)
                    : (backingOff || ready > notBefore) ? .waiting(until: ready) : .running
                try await clock.sleep(until: ready)
            }
        } catch {
            queue.removeAll { $0.id == ticket.id }
            cancelledTickets.remove(ticket.id)
            if !busy, queue.isEmpty { state = .idle }
            wakeAll()
            throw error
        }
    }

    private func readyTime(for priority: Priority, now: Date) -> Date {
        var ready = max(notBefore, pausedUntil)
        if priority == .background, batchCount >= configuration.batchSize,
           now.timeIntervalSince(lastFinish) < configuration.batchRest {
            ready = max(ready, lastFinish.addingTimeInterval(configuration.batchRest))
        }
        return ready
    }

    /// Ahead of every lower priority, behind everything of its own (FIFO).
    /// A retry keeps its original place.
    private func insert(_ ticket: Ticket) {
        let index = queue.firstIndex {
            $0.priority < ticket.priority || ($0.priority == ticket.priority && $0.id > ticket.id)
        } ?? queue.endIndex
        queue.insert(ticket, at: index)
        wakeAll()
    }

    private func finish(_ ticket: Ticket, rateLimit retryAfter: TimeInterval?,
                        failed: Bool = false, retrying: Bool = false) {
        let now = clock.now
        busy = false
        lastFinish = now
        notBefore = now.addingTimeInterval(jittered(configuration.spacing, configuration.spacingJitter))
        backingOff = false
        if let retryAfter {
            recordRateLimit(retryAfter: retryAfter, now: now)
        } else if !failed {
            consecutiveLimits = 0
            breakerTrips = 0
        }
        if queue.isEmpty, !retrying {
            state = .idle
        } else if pausedUntil > now {
            state = .paused(until: pausedUntil)
        } else if backingOff {
            state = .waiting(until: notBefore)
        } else {
            state = .running
        }
        wakeAll()
    }

    private func recordRateLimit(retryAfter: TimeInterval, now: Date) {
        let base = configuration.backoffBase * pow(2, Double(consecutiveLimits))
        let wait = min(configuration.maxBackoff, jittered(max(retryAfter, base), configuration.backoffJitter))
        consecutiveLimits += 1
        notBefore = max(notBefore, now.addingTimeInterval(wait))
        backingOff = true

        recentLimits = recentLimits.filter { now.timeIntervalSince($0) < configuration.breakerWindow } + [now]
        if recentLimits.count >= configuration.breakerThreshold {
            let pause = configuration.breakerPause * pow(2, Double(breakerTrips))
            breakerTrips += 1
            recentLimits = []
            pausedUntil = max(pausedUntil, now.addingTimeInterval(pause))
        }
    }

    private func jittered(_ value: TimeInterval, _ fraction: Double) -> TimeInterval {
        max(0, value * random((1 - fraction)...(1 + fraction)))
    }

    // MARK: - signalling

    private func waitForSignal(_ id: Int) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                if cancelledTickets.remove(id) != nil || Task.isCancelled {
                    c.resume(throwing: CancellationError())
                } else {
                    wakers[id] = c
                }
            }
        } onCancel: {
            Task { await self.cancelWait(id) }
        }
    }

    private func cancelWait(_ id: Int) {
        if let c = wakers.removeValue(forKey: id) {
            c.resume(throwing: CancellationError())
        } else if queue.contains(where: { $0.id == id }) {
            cancelledTickets.insert(id)
        }
    }

    private func wakeAll() {
        let all = wakers
        wakers = [:]
        for c in all.values { c.resume() }
    }
}

/// Time as the scheduler sees it, so tests can run hours of back-off instantly.
public protocol AO3Clock: Sendable {
    var now: Date { get }
    /// Returns at `deadline` or throws `CancellationError`.
    func sleep(until deadline: Date) async throws
}

public struct SystemClock: AO3Clock {
    public init() {}
    public var now: Date { Date() }
    public func sleep(until deadline: Date) async throws {
        let seconds = deadline.timeIntervalSinceNow
        if seconds > 0 { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
        try Task.checkCancellation()
    }
}

import XCTest
@testable import AO3Kit

/// A clock whose sleeps return at once, moving time forward to the deadline.
final class TestClock: AO3Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = Date(timeIntervalSince1970: 1_800_000_000)) { current = start }

    var now: Date { lock.withLock { current } }

    func sleep(until deadline: Date) async throws {
        try Task.checkCancellation()
        lock.withLock { current = max(current, deadline) }
        await Task.yield()
    }
}

/// Collects values from concurrent tasks.
actor Log<T: Sendable> {
    private(set) var items: [T] = []
    func add(_ item: T) { items.append(item) }
}

/// An operation that waits until opened.
actor Gate {
    private var open = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var entered = false

    func wait() async {
        entered = true
        if open { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        open = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

final class AO3SchedulerTests: XCTestCase {
    /// No jitter: every random draw is the middle of its range.
    let noJitter: @Sendable (ClosedRange<Double>) -> Double = { ($0.lowerBound + $0.upperBound) / 2 }

    func makeScheduler(_ clock: TestClock, _ adjust: (inout AO3Scheduler.Configuration) -> Void = { _ in }) -> AO3Scheduler {
        var config = AO3Scheduler.Configuration()
        adjust(&config)
        return AO3Scheduler(configuration: config, clock: clock, random: noJitter)
    }

    /// Seconds since `clock` started, for each operation start.
    func offsets(_ dates: [Date], from start: Date) -> [Double] {
        dates.map { ($0.timeIntervalSince(start) * 1000).rounded() / 1000 }
    }

    func testSpacesRequests() async throws {
        let clock = TestClock(), start = clock.now
        let scheduler = makeScheduler(clock)
        var starts: [Date] = []
        for _ in 0..<3 { starts.append(try await scheduler.run(.user) { clock.now }) }
        XCTAssertEqual(offsets(starts, from: start), [0, 3, 6])
    }

    func testSpacingJitterStaysWithinTwentyPercent() async throws {
        let clock = TestClock(), start = clock.now
        let scheduler = AO3Scheduler(clock: clock, random: { $0.lowerBound })
        _ = try await scheduler.run { 0 }
        let second = try await scheduler.run { clock.now }
        XCTAssertEqual(second.timeIntervalSince(start), 2.4, accuracy: 0.001)
    }

    func testBacksOffExponentiallyThenSucceeds() async throws {
        let clock = TestClock(), start = clock.now
        let scheduler = makeScheduler(clock) { $0.breakerThreshold = 10 }
        let starts = Log<Date>()
        let value = try await scheduler.run(.user) { () -> Int in
            await starts.add(clock.now)
            if await starts.items.count < 3 { throw AO3Error.rateLimited(retryAfter: nil) }
            return 7
        }
        XCTAssertEqual(value, 7)
        // 20 s, then 40 s.
        let seen = await starts.items
        XCTAssertEqual(offsets(seen, from: start), [0, 20, 60])
    }

    func testRetryAfterWinsWhenLonger() async throws {
        let clock = TestClock(), start = clock.now
        let scheduler = makeScheduler(clock)
        let starts = Log<Date>()
        _ = try await scheduler.run(.user) { () -> Int in
            await starts.add(clock.now)
            if await starts.items.count == 1 { throw AO3Error.rateLimited(retryAfter: 120) }
            return 0
        }
        let seen = await starts.items
        XCTAssertEqual(offsets(seen, from: start), [0, 120])
    }

    func testBackoffIsCappedAndGivesUp() async throws {
        let clock = TestClock(), start = clock.now
        let scheduler = makeScheduler(clock) {
            $0.backoffBase = 600
            $0.maxAttempts = 3
            $0.breakerThreshold = 10
        }
        let starts = Log<Date>()
        do {
            _ = try await scheduler.run(.user) { () -> Int in
                await starts.add(clock.now)
                throw AO3Error.rateLimited(retryAfter: nil)
            }
            XCTFail("expected a rate limit")
        } catch AO3Error.rateLimited {}
        // 600 s, then 1200 s capped to 900.
        let seen = await starts.items
        XCTAssertEqual(offsets(seen, from: start), [0, 600, 1500])
    }

    func testCircuitBreakerPausesEverythingAndDoubles() async throws {
        let clock = TestClock(), start = clock.now
        let scheduler = makeScheduler(clock) {
            $0.spacing = 0
            $0.backoffBase = 0.001
            $0.maxAttempts = 3
        }
        let states = Log<AO3Scheduler.State>()
        let watcher = Task {
            for await state in await scheduler.stateUpdates() { await states.add(state) }
        }
        let failing: @Sendable () async throws -> Date = { throw AO3Error.rateLimited(retryAfter: nil) }

        // Three rate limits in a row trip the breaker: ten minutes.
        await XCTAssertThrowsRateLimit { try await scheduler.run(.background, failing) }
        let afterFirstTrip = try await scheduler.run(.user) { clock.now }
        XCTAssertEqual(afterFirstTrip.timeIntervalSince(start), 600, accuracy: 0.1)

        // A success resets the doubling; tripping twice without one doubles it.
        await XCTAssertThrowsRateLimit { try await scheduler.run(.user, failing) }
        let t1 = clock.now
        await XCTAssertThrowsRateLimit { try await scheduler.run(.user, failing) }
        let t2 = clock.now
        XCTAssertEqual(t2.timeIntervalSince(t1), 600, accuracy: 0.1)
        let afterSecondTrip = try await scheduler.run(.user) { clock.now }
        XCTAssertEqual(afterSecondTrip.timeIntervalSince(t2), 1200, accuracy: 0.1)

        let final = await scheduler.state
        XCTAssertEqual(final, .idle)
        for _ in 0..<1000 where await states.items.last != .idle { await Task.yield() }
        let seen = await states.items
        let pauses = seen.compactMap { if case .paused(let until) = $0 { until.timeIntervalSince(start) } else { nil } }
        XCTAssertEqual(pauses.first ?? 0, 600, accuracy: 0.1, "\(seen)")
        XCTAssertTrue(seen.contains(.running))
        XCTAssertEqual(seen.last, .idle)
        watcher.cancel()
    }

    func testUserRequestsGoFirst() async throws {
        let clock = TestClock()
        let scheduler = makeScheduler(clock) { $0.spacing = 0 }
        let gate = Gate()
        let order = Log<String>()

        let first = Task { try await scheduler.run(.user) { await gate.wait(); await order.add("first") } }
        while !(await gate.entered) { await Task.yield() }

        var tasks: [Task<Void, Error>] = []
        for (name, priority) in [("bg1", AO3Scheduler.Priority.background), ("bg2", .background), ("user", .user)] {
            tasks.append(Task { try await scheduler.run(priority) { await order.add(name) } })
            while await scheduler.pendingCount < tasks.count { await Task.yield() }
        }
        await gate.release()
        try await first.value
        for t in tasks { try await t.value }
        let ran = await order.items
        XCTAssertEqual(ran, ["first", "user", "bg1", "bg2"])
    }

    func testBackgroundRestsBetweenBatches() async throws {
        let clock = TestClock(), start = clock.now
        let scheduler = makeScheduler(clock) {
            $0.spacing = 1
            $0.batchSize = 3
        }
        var starts: [Date] = []
        for _ in 0..<7 { starts.append(try await scheduler.run(.background) { clock.now }) }
        XCTAssertEqual(offsets(starts, from: start), [0, 1, 2, 62, 63, 64, 124])
    }

    func testUserRequestsSkipTheBatchRest() async throws {
        let clock = TestClock(), start = clock.now
        let scheduler = makeScheduler(clock) {
            $0.spacing = 1
            $0.batchSize = 2
        }
        for _ in 0..<2 { _ = try await scheduler.run(.background) { 0 } }
        let user = try await scheduler.run(.user) { clock.now }
        XCTAssertEqual(user.timeIntervalSince(start), 2, accuracy: 0.001)
        let background = try await scheduler.run(.background) { clock.now }
        XCTAssertEqual(background.timeIntervalSince(start), 62, accuracy: 0.001)
    }

    func testCancelledWaiterLeavesTheQueue() async throws {
        let clock = TestClock()
        let scheduler = makeScheduler(clock) { $0.spacing = 0 }
        let gate = Gate()
        let first = Task { try await scheduler.run(.user) { await gate.wait() } }
        while !(await gate.entered) { await Task.yield() }

        let queued = Task { try await scheduler.run(.background) { XCTFail("should not run") } }
        while await scheduler.pendingCount < 1 { await Task.yield() }
        queued.cancel()
        do {
            try await queued.value
            XCTFail("expected cancellation")
        } catch is CancellationError {}
        let pending = await scheduler.pendingCount
        XCTAssertEqual(pending, 0)

        await gate.release()
        try await first.value
        let after = try await scheduler.run(.user) { 1 }
        XCTAssertEqual(after, 1)
    }

    func testOtherErrorsPassThroughWithoutRetry() async {
        let scheduler = makeScheduler(TestClock())
        let calls = Log<Int>()
        do {
            _ = try await scheduler.run(.user) { () -> Int in
                await calls.add(1)
                throw AO3Error.notFound
            }
            XCTFail("expected notFound")
        } catch {
            XCTAssertEqual(error as? AO3Error, .notFound)
        }
        let count = await calls.items.count
        XCTAssertEqual(count, 1)
    }

    // MARK: - Retry-After

    func testRetryAfterSecondsAndDates() {
        let now = ISO8601DateFormatter().date(from: "2026-10-25T18:30:00Z")!
        XCTAssertEqual(RetryAfter.seconds("120", now: now), 120)
        XCTAssertEqual(RetryAfter.seconds(" 5 ", now: now), 5)
        XCTAssertEqual(RetryAfter.seconds("Sun, 25 Oct 2026 18:32:00 GMT", now: now), 120)
        XCTAssertEqual(RetryAfter.seconds("Sunday, 25-Oct-26 18:31:00 GMT", now: now), 60)
        XCTAssertEqual(RetryAfter.seconds("Sun Oct 25 18:30:30 2026", now: now), 30)
        XCTAssertEqual(RetryAfter.seconds("Sun, 25 Oct 2026 18:00:00 GMT", now: now), 0)
        XCTAssertNil(RetryAfter.seconds("soon", now: now))
    }

    func testRateLimitResponsesCarryRetryAfter() {
        let now = ISO8601DateFormatter().date(from: "2026-10-25T18:30:00Z")!
        let url = URL(string: "https://archiveofourown.org/works/1")!
        for (code, header, expected) in [(429, "Sun, 25 Oct 2026 18:35:00 GMT", 300), (503, "30", 30), (525, nil, nil)] as [(Int, String?, Int?)] {
            let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: nil,
                                           headerFields: header.map { ["Retry-After": $0] })!
            XCTAssertThrowsError(try AO3Client.check(response, now: now)) {
                XCTAssertEqual($0 as? AO3Error, .rateLimited(retryAfter: expected))
            }
        }
    }
}

func XCTAssertThrowsRateLimit<T>(_ body: () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async {
    do {
        _ = try await body()
        XCTFail("expected a rate limit", file: file, line: line)
    } catch AO3Error.rateLimited {
    } catch {
        XCTFail("unexpected \(error)", file: file, line: line)
    }
}

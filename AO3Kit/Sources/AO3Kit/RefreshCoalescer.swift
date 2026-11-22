import Foundation

/// Runs one piece of work at a time (a library scan) for many callers.
/// A call while it's running doesn't start a second run alongside it, and
/// doesn't just wait for that run either: the run began before the call
/// and may have read the folder before the caller's change (a delete, an
/// add), so it would hand back the old state. Instead the call asks for one
/// more run after it, and returns once that run is done. Any number of
/// calls during a run share that one extra run.
@MainActor
public final class RefreshCoalescer {
    private let work: @MainActor () async -> Void
    private var running: Task<Void, Never>?
    private var again = false

    public init(_ work: @escaping @MainActor () async -> Void) {
        self.work = work
    }

    public var isRunning: Bool { running != nil }

    /// Runs the work, or, if it's running, makes sure it runs again
    /// afterwards; returns once a run that started after this call is done.
    public func run() async {
        if let running {
            again = true
            await running.value
            return
        }
        let task = Task { @MainActor in
            repeat {
                self.again = false
                await self.work()
            } while self.again
            // Same step as the last check, with no suspension between: a
            // call can't join a run that has already decided to stop.
            self.running = nil
        }
        running = task
        await task.value
    }
}

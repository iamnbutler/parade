import Foundation

/// Tells the model when the library folder changed, instead of it walking
/// the folder on a timer. In iCloud that's a metadata query (iCloud's own
/// index, kept by the system): it reports files arriving, changing,
/// downloading or disappearing — from this device or another. A burst of
/// changes (a sync landing, a download) arrives as one call.
@MainActor
final class LibraryWatcher {
    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var pending: Task<Void, Never>?
    private let onChange: @MainActor () -> Void

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    /// Starts watching the app's iCloud Documents folder. Folders outside
    /// iCloud (no iCloud account, a test library) aren't watched; they
    /// refresh when the app comes forward.
    func watchCloud() {
        stop()
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemFSNameKey)
        // Batches changes on the system side, too.
        query.notificationBatchingInterval = 2
        let center = NotificationCenter.default
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(center.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.changed() }
            })
        }
        self.query = query
        query.start()
    }

    func stop() {
        query?.stop()
        query = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        pending?.cancel()
        pending = nil
    }

    private func changed() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.onChange()
        }
    }
}

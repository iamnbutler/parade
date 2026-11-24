import Foundation
import AO3Kit

/// Tells the model when the library folder changed, instead of it walking
/// the folder on a timer. In iCloud that's a metadata query (iCloud's own
/// index, kept by the system): it reports files arriving, changing,
/// downloading or disappearing — from this device or another. A burst of
/// changes (a sync landing, a download) arrives as one call, saying what
/// kind of change it was: a fic (walk the library), a state file like
/// Favorites.txt (re-read it), or Backups and Trash. Parade's own writes
/// come back through here too, so a favorite toggled mustn't cost a walk.
@MainActor
final class LibraryWatcher {
    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var pending: Task<Void, Never>?
    private var root: URL?
    /// What the changes so far in this burst need.
    private var accumulated: LibraryChange = []
    private let onChange: @MainActor (LibraryChange) -> Void

    init(onChange: @escaping @MainActor (LibraryChange) -> Void) {
        self.onChange = onChange
    }

    /// Starts watching the app's iCloud Documents folder. Folders outside
    /// iCloud (no iCloud account, a test library) aren't watched; they
    /// refresh when the app comes forward.
    func watchCloud(root: URL) {
        stop()
        self.root = root
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemFSNameKey)
        // Batches changes on the system side, too.
        query.notificationBatchingInterval = 2
        let center = NotificationCenter.default
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(center.addObserver(forName: name, object: query, queue: .main) { [weak self] note in
                let paths = Self.paths(in: note)
                MainActor.assumeIsolated { self?.changed(paths: paths) }
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
        accumulated = []
    }

    /// The paths an update names; nil for the first gathering (or an
    /// update that names none), which means "assume anything changed".
    private nonisolated static func paths(in note: Notification) -> [String]? {
        guard note.name == .NSMetadataQueryDidUpdate, let info = note.userInfo else { return nil }
        var paths: [String] = []
        for key in [NSMetadataQueryUpdateAddedItemsKey, NSMetadataQueryUpdateChangedItemsKey,
                    NSMetadataQueryUpdateRemovedItemsKey] {
            for item in info[key] as? [NSMetadataItem] ?? [] {
                guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { return nil }
                paths.append(path)
            }
        }
        return paths.isEmpty ? nil : paths
    }

    private func changed(paths: [String]?) {
        if let paths, let root {
            accumulated.formUnion(LibraryChange.classify(paths: paths, root: root))
        } else {
            accumulated = .all
        }
        guard !accumulated.isEmpty else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            let change = self.accumulated
            self.accumulated = []
            self.onChange(change)
        }
    }
}

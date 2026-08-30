import Foundation
import SwiftUI
import AO3Kit
#if os(macOS)
import AppKit
#endif

/// One fic in the library. Derived entirely from the filesystem — the
/// `Author/Title.epub` tree is the single source of truth; there is no
/// separate database to drift out of sync.
struct LibraryItem: Identifiable, Equatable {
    let author: String
    let title: String
    /// The real EPUB location (even when only an iCloud placeholder exists yet).
    let url: URL
    let date: Date
    /// False while the file is still an undownloaded ".….icloud" placeholder.
    let isDownloaded: Bool

    var id: String { author + "/" + title }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var library: [(author: String, items: [LibraryItem])] = []
    @Published var statusLines: [String] = []
    @Published var isWorking = false
    @Published var destinationLabel = ""
    @Published var libraryError: String?

    private let client = AO3Client()
    private let defaults = UserDefaults.standard
    private(set) var destinationRoot: URL
    /// Held for the app's lifetime when the destination is a user-picked folder.
    private var scopedAccess = false

    #if os(macOS)
    @Published var autoImport: Bool {
        didSet { defaults.set(autoImport, forKey: Keys.autoImport) }
    }
    private var timer: Timer?
    /// relativePath → last-imported mtime, so each EPUB version reaches
    /// Apple Books exactly once.
    private var imported: [String: TimeInterval]
    #endif

    private enum Keys {
        static let folderBookmark = "destinationBookmark.v1"
        static let autoImport = "autoImport.v1"
        static let imported = "importedFiles.v1"
        static let baselinedFolder = "baselinedFolder.v1"
    }

    init() {
        #if os(macOS)
        autoImport = defaults.object(forKey: Keys.autoImport) as? Bool ?? true
        imported = defaults.dictionary(forKey: Keys.imported) as? [String: TimeInterval] ?? [:]
        #endif
        destinationRoot = Self.defaultRoot()
        restoreCustomDestination()
        updateDestinationLabel()
        refreshLibrary()
        #if os(macOS)
        startWatching()
        #endif
    }

    // MARK: - destination folder

    private static func defaultRoot() -> URL {
        #if os(iOS)
        // Documents/Fan Fiction — visible in Files as
        // "On My iPhone › Parade › Fan Fiction".
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = documents.appendingPathComponent("Fan Fiction", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Early builds saved author folders directly in Documents; pull them in.
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: documents, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for entry in entries where entry.lastPathComponent != "Fan Fiction" {
                let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                guard isDir else { continue }
                try? FileManager.default.moveItem(
                    at: entry, to: root.appendingPathComponent(entry.lastPathComponent))
            }
        }
        return root
        #else
        // iCloud Drive/Fan Fiction when iCloud Drive exists (matches what the
        // phone syncs to), otherwise ~/Documents/Fan Fiction.
        let home = FileManager.default.homeDirectoryForCurrentUser
        let icloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        let base = FileManager.default.fileExists(atPath: icloud.path)
            ? icloud
            : home.appendingPathComponent("Documents", isDirectory: true)
        let root = base.appendingPathComponent("Fan Fiction", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
        #endif
    }

    private func restoreCustomDestination() {
        guard let bookmark = defaults.data(forKey: Keys.folderBookmark) else { return }
        var stale = false
        #if os(macOS)
        let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], bookmarkDataIsStale: &stale)
        #else
        let resolved = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale)
        #endif
        guard let url = resolved, url.startAccessingSecurityScopedResource() else {
            defaults.removeObject(forKey: Keys.folderBookmark)
            return
        }
        if stale, let fresh = try? Self.bookmarkData(for: url) {
            defaults.set(fresh, forKey: Keys.folderBookmark)
        }
        destinationRoot = url
        scopedAccess = true
    }

    private static func bookmarkData(for url: URL) throws -> Data {
        #if os(macOS)
        try url.bookmarkData(options: [.withSecurityScope])
        #else
        try url.bookmarkData()
        #endif
    }

    func setDestination(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            status("⚠️ Couldn't get access to that folder.")
            return
        }
        do {
            let bookmark = try Self.bookmarkData(for: url)
            if scopedAccess { destinationRoot.stopAccessingSecurityScopedResource() }
            defaults.set(bookmark, forKey: Keys.folderBookmark)
            destinationRoot = url
            scopedAccess = true
        } catch {
            url.stopAccessingSecurityScopedResource()
            status("⚠️ Couldn't save that folder choice: \(error.localizedDescription)")
        }
        didChangeDestination()
    }

    func resetDestination() {
        if scopedAccess { destinationRoot.stopAccessingSecurityScopedResource() }
        scopedAccess = false
        defaults.removeObject(forKey: Keys.folderBookmark)
        destinationRoot = Self.defaultRoot()
        didChangeDestination()
    }

    private func didChangeDestination() {
        updateDestinationLabel()
        refreshLibrary()
        #if os(macOS)
        scan()
        #endif
    }

    var usesCustomDestination: Bool { scopedAccess }

    private func updateDestinationLabel() {
        if scopedAccess {
            destinationLabel = destinationRoot.lastPathComponent
        } else {
            #if os(iOS)
            destinationLabel = "On My iPhone › Parade › Fan Fiction"
            #else
            destinationLabel = destinationRoot.path.contains("Mobile Documents")
                ? "iCloud Drive › Fan Fiction"
                : "Documents › Fan Fiction"
            #endif
        }
    }

    // MARK: - library (filesystem is the source of truth)

    func refreshLibrary() {
        let fm = FileManager.default
        var groups: [(author: String, items: [LibraryItem])] = []
        let authorDirs: [URL]
        do {
            authorDirs = try fm.contentsOfDirectory(
                at: destinationRoot, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])
            libraryError = nil
        } catch {
            // Don't swallow this: on macOS a denied Files-and-Folders / iCloud
            // Drive permission looks exactly like an empty folder otherwise.
            libraryError = "Can't read \(destinationRoot.path): \(error.localizedDescription)"
            library = []
            return
        }

        for dir in authorDirs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let files = (try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [])) ?? []
            var items: [LibraryItem] = []
            for file in files {
                if let item = Self.libraryItem(for: file, author: dir.lastPathComponent) {
                    items.append(item)
                    if !item.isDownloaded {
                        // Ask iCloud to materialize placeholders so they
                        // become readable (and shareable) soon.
                        try? fm.startDownloadingUbiquitousItem(at: item.url)
                    }
                }
            }
            guard !items.isEmpty else { continue }
            items.sort { $0.date > $1.date }
            groups.append((author: dir.lastPathComponent, items: items))
        }
        groups.sort { $0.author.localizedCaseInsensitiveCompare($1.author) == .orderedAscending }
        library = groups
    }

    private static func libraryItem(for file: URL, author: String) -> LibraryItem? {
        let name = file.lastPathComponent
        let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
        if name.lowercased().hasSuffix(".epub") {
            return LibraryItem(
                author: author, title: file.deletingPathExtension().lastPathComponent,
                url: file, date: date, isDownloaded: true)
        }
        // iCloud placeholder: ".Title.epub.icloud" stands in for "Title.epub".
        if name.hasPrefix("."), name.hasSuffix(".icloud") {
            let realName = String(name.dropFirst().dropLast(".icloud".count))
            guard realName.lowercased().hasSuffix(".epub") else { return nil }
            let realURL = file.deletingLastPathComponent().appendingPathComponent(realName)
            return LibraryItem(
                author: author, title: (realName as NSString).deletingPathExtension,
                url: realURL, date: date, isDownloaded: false)
        }
        return nil
    }

    func delete(_ item: LibraryItem) {
        let fm = FileManager.default
        try? fm.removeItem(at: item.url)
        let dir = item.url.deletingLastPathComponent()
        if let remaining = try? fm.contentsOfDirectory(atPath: dir.path), remaining.isEmpty {
            try? fm.removeItem(at: dir)
        }
        #if os(macOS)
        imported.removeValue(forKey: relativePath(of: item.url))
        persistImported()
        #endif
        refreshLibrary()
    }

    // MARK: - download pipeline

    func handle(_ text: String) async {
        guard !isWorking else { return }
        guard let link = AO3Link(text: text) else {
            status("⚠️ \(AO3Error.notAnAO3Link.localizedDescription)")
            return
        }
        isWorking = true
        statusLines = []
        defer { isWorking = false }

        do {
            let ids = try await client.workIDs(for: link)
            if case .series = link {
                status("Series with \(ids.count) work\(ids.count == 1 ? "" : "s")…")
            }
            for (index, id) in ids.enumerated() {
                if index > 0 {
                    // Be polite to AO3 between series downloads.
                    try? await Task.sleep(for: .seconds(1.5))
                }
                do {
                    try await downloadWork(id: id)
                } catch {
                    status("⚠️ Work \(id): \(error.localizedDescription)")
                }
            }
        } catch {
            status("⚠️ \(error.localizedDescription)")
        }
        refreshLibrary()
        #if os(macOS)
        scan()
        #endif
    }

    private func downloadWork(id: Int) async throws {
        status("Fetching work \(id)…")
        let work = try await client.fetchWork(id: id)
        status("Downloading “\(work.title)” by \(work.authorLabel)…")
        let temp = try await client.downloadEPUB(work)
        let dest = try Organizer(root: destinationRoot).place(temp, for: work)
        status("✓ Saved \(relativePath(of: dest))")
    }

    func status(_ line: String) {
        statusLines.append(line)
        if statusLines.count > 8 { statusLines.removeFirst() }
    }

    private func relativePath(of url: URL) -> String {
        url.path.replacingOccurrences(of: destinationRoot.path + "/", with: "")
    }

    // MARK: - Apple Books (macOS)

    #if os(macOS)
    /// Sends one fic to Apple Books (silent import) and remembers it.
    func addToBooks(_ item: LibraryItem) {
        guard sendToBooks([item.url]) else { return }
        markImported(item.url)
        persistImported()
        status("→ Books: \(item.title)")
    }

    @discardableResult
    private func sendToBooks(_ urls: [URL]) -> Bool {
        guard let books = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iBooksX") else {
            status("⚠️ Apple Books not found")
            return false
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.open(urls, withApplicationAt: books, configuration: config)
        return true
    }

    /// "Opening" an EPUB is the only supported way into Books' library, but it
    /// also opens a reader window per book — close them so a bulk import
    /// doesn't bury the user in 300 windows. Best-effort AppleScript (the
    /// first use prompts once to allow controlling Books).
    private func closeBooksWindows() {
        let script = NSAppleScript(source: #"tell application "Books" to close every window"#)
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
    }

    private func markImported(_ url: URL) {
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970 ?? 0
        imported[relativePath(of: url)] = mtime
    }

    private func startWatching() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
        scan()
    }

    /// One poll of the library folder: refresh the view, and auto-import
    /// EPUBs that arrived or changed since the last look.
    func scan() {
        refreshLibrary()
        let downloaded = library.flatMap(\.items).filter(\.isDownloaded)

        // First look at a folder: baseline its existing contents as already
        // imported, so switching folders never mass-imports by surprise —
        // "Import a Folder of Books…" is the explicit way to do that.
        if defaults.string(forKey: Keys.baselinedFolder) != destinationRoot.path {
            imported = [:]
            downloaded.forEach { markImported($0.url) }
            persistImported()
            defaults.set(destinationRoot.path, forKey: Keys.baselinedFolder)
            if !downloaded.isEmpty {
                status("Found \(downloaded.count) existing book\(downloaded.count == 1 ? "" : "s") — use “Import a Folder of Books…” to send them to Apple Books.")
            }
            return
        }

        guard autoImport else { return }
        let currentPaths = Set(downloaded.map { relativePath(of: $0.url) })
        let fresh = downloaded.filter { item in
            let mtime = item.date.timeIntervalSince1970
            if let seen = imported[relativePath(of: item.url)], seen >= mtime { return false }
            return true
        }

        // Auto-import is for single-URL downloads (pasted here, or synced in
        // from the phone one fic at a time). A large batch landing at once —
        // an initial iCloud sync, a folder copied in by hand — is bulk:
        // baseline it and leave Books to the explicit "Import All".
        if fresh.count > 20 {
            fresh.forEach { markImported($0.url) }
            imported = imported.filter { currentPaths.contains($0.key) }
            persistImported()
            status("Found \(fresh.count) new fics — bulk arrival, skipping auto-import. Use “Import All to Apple Books” to send them.")
            return
        }

        var imports = 0
        for item in fresh {
            guard sendToBooks([item.url]) else { return }
            markImported(item.url)
            status("→ Books: \(item.title)")
            imports += 1
        }
        if imports > 0 {
            // Don't leave reader windows piling up on an unattended Mac.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1500))
                self.closeBooksWindows()
            }
        }
        // Forget deleted files so a future re-download imports again.
        imported = imported.filter { currentPaths.contains($0.key) }
        persistImported()
    }

    /// Merges an existing `[Author]/…/[epub]` tree (e.g. a Calibre library)
    /// INTO the library folder — the folder is the source of truth, so
    /// getting fics into Parade (and from there into Books, via the watcher)
    /// means getting the files into the folder. Files are moved; duplicates
    /// already in the library are left in place at the source.
    func mergeFolder(_ folder: URL) async {
        let fm = FileManager.default
        var moved = 0, skipped = 0, failed = 0
        guard let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            status("⚠️ Can't read \(folder.lastPathComponent)")
            return
        }
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "epub" {
            // Author = the top-level folder the epub sits under (Calibre nests
            // Author/Title/file.epub — the first component is still the author).
            let relParts = url.path
                .replacingOccurrences(of: folder.path + "/", with: "")
                .components(separatedBy: "/")
            let author = relParts.count > 1 ? relParts[0] : "Unknown Author"
            let authorDir = destinationRoot.appendingPathComponent(Organizer.sanitize(author), isDirectory: true)
            let dest = authorDir.appendingPathComponent(url.lastPathComponent)
            if fm.fileExists(atPath: dest.path) {
                skipped += 1
                continue
            }
            do {
                try fm.createDirectory(at: authorDir, withIntermediateDirectories: true)
                do {
                    try fm.moveItem(at: url, to: dest)
                } catch {
                    // Cross-volume moves fail; copy then remove.
                    try fm.copyItem(at: url, to: dest)
                    try? fm.removeItem(at: url)
                }
                // Baseline the file so the watcher does NOT auto-import it —
                // Books auto-import is only for single-URL downloads; bulk
                // goes through the explicit "Import All to Apple Books".
                markImported(dest)
                moved += 1
            } catch {
                failed += 1
            }
        }
        persistImported()
        var summary = "✓ Merged \(moved) fic\(moved == 1 ? "" : "s") into the library"
        if skipped > 0 { summary += ", \(skipped) already there" }
        if failed > 0 { summary += ", \(failed) failed" }
        status(summary)
        if moved > 0 {
            status("Use “Import All to Apple Books” to send them to Books.")
        }
        refreshLibrary()
    }

    /// Explicit bulk action: send every EPUB in the library to Apple Books,
    /// batched, tidying the reader windows Books opens along the way.
    func importAllToBooks() async {
        refreshLibrary()
        let epubs = library.flatMap(\.items).filter(\.isDownloaded).map(\.url)
        guard !epubs.isEmpty else {
            status("⚠️ Library is empty")
            return
        }
        status("Importing \(epubs.count) book\(epubs.count == 1 ? "" : "s") to Apple Books…")
        for start in stride(from: 0, to: epubs.count, by: 20) {
            let batch = Array(epubs[start..<min(start + 20, epubs.count)])
            guard sendToBooks(batch) else { return }
            try? await Task.sleep(for: .milliseconds(1500))
            closeBooksWindows()
        }
        epubs.forEach { markImported($0) }
        persistImported()
        status("✓ Sent \(epubs.count) book\(epubs.count == 1 ? "" : "s") to Apple Books")
    }

    private func persistImported() {
        defaults.set(imported, forKey: Keys.imported)
    }
    #endif
}

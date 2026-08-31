import Foundation

/// Moves older library stores into the current `<root>/<provider>/<Author>/`
/// layout. Everything is move-only and idempotent: nothing is ever deleted,
/// a duplicate at the destination sends the source copy to Backups/ instead,
/// and running it again over an already-migrated (or empty) store is a no-op.
public enum LibraryMigrator {
    public struct Result: Sendable {
        /// EPUBs moved into the new root.
        public var movedEPUBs = 0
        /// Lines found in the store's Favorites.txt, for the caller to merge.
        public var favoriteLines: [String] = []
        /// Real URLs of iCloud placeholders that couldn't move yet — the
        /// caller should request their download and migrate again later.
        public var pendingDownloads: [URL] = []
    }

    /// Merges a whole legacy store (any historical layout) into `root`:
    ///  - `<store>/<Author>/<Title>.epub`            → `<root>/ao3/<Author>/`
    ///  - `<store>/<provider>/<Author>/<Title>.epub` → `<root>/<provider>/<Author>/`
    ///  - `<store>/Backups/…`                        → `<root>/Backups/…`
    ///  - `<store>/Favorites.txt`                    → returned, file kept in Backups/
    public static func merge(store: URL, into root: URL) throws -> Result {
        let fm = FileManager.default
        var result = Result()
        guard store.standardizedFileURL.path != root.standardizedFileURL.path,
              fm.fileExists(atPath: store.path)
        else { return result }

        let entries = try fm.contentsOfDirectory(
            at: store, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        for entry in entries {
            let name = entry.lastPathComponent
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if !isDir {
                if name == "Favorites.txt" {
                    result.favoriteLines = favoriteLines(of: entry)
                    try? retire(entry, root: root)
                }
                continue
            }
            if name == Organizer.backupsFolder {
                mergeBackups(entry, into: root, result: &result)
            } else if knownProviders.contains(name) {
                // Provider folder: its subfolders are authors.
                for author in subdirectories(of: entry) {
                    moveAuthorDir(author, toProvider: name, root: root, result: &result)
                }
                pruneIfEmpty(entry)
            } else if hasEPUBContent(entry) {
                // Legacy author folder sitting directly in the store.
                moveAuthorDir(entry, toProvider: Organizer.ao3, root: root, result: &result)
            } else if !subdirectories(of: entry).isEmpty {
                // A wrapper like the old "Fan Fiction" folder — a store
                // nested inside this one.
                if let nested = try? merge(store: entry, into: root) {
                    result.movedEPUBs += nested.movedEPUBs
                    result.favoriteLines += nested.favoriteLines
                    result.pendingDownloads += nested.pendingDownloads
                }
                pruneIfEmpty(entry)
            } else {
                pruneIfEmpty(entry)
            }
        }
        return result
    }

    /// Provider folders merge() recognizes as such — extend when a new
    /// source joins Organizer.
    private static let knownProviders: Set<String> = [Organizer.ao3]

    /// Fixes stray content inside an already-current root, so hand-dropped
    /// files still land in the library: a root-level folder holding EPUBs is
    /// treated as an author and filed under ao3/. Cheap when there's nothing
    /// to do — safe to run on every library refresh.
    public static func normalizeLayout(root: URL) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        else { return }
        var result = Result()
        for entry in entries {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir, entry.lastPathComponent != Organizer.backupsFolder else { continue }
            if !directEPUBs(in: entry).isEmpty {
                // Folder of EPUBs at the root — a legacy/hand-dropped author dir.
                moveAuthorDir(entry, toProvider: Organizer.ao3, root: root, result: &result)
            }
        }
    }

    // MARK: - pieces

    private static func directEPUBs(in dir: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return files.filter { $0.pathExtension.lowercased() == "epub" }
    }

    /// True when the folder directly holds EPUBs — downloaded, or still
    /// iCloud placeholders (".Title.epub.icloud").
    private static func hasEPUBContent(_ dir: URL) -> Bool {
        if !directEPUBs(in: dir).isEmpty { return true }
        let all = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [])) ?? []
        return all.contains {
            $0.lastPathComponent.hasPrefix(".") && $0.lastPathComponent.hasSuffix(".epub.icloud")
        }
    }

    private static func subdirectories(of dir: URL) -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        return entries.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }
    }

    /// Moves every EPUB in `authorDir` to `<root>/<provider>/<author>/`,
    /// noting iCloud placeholders for later, then prunes the dir if empty.
    private static func moveAuthorDir(_ authorDir: URL, toProvider provider: String, root: URL, result: inout Result) {
        let fm = FileManager.default
        let destDir = root
            .appendingPathComponent(provider, isDirectory: true)
            .appendingPathComponent(authorDir.lastPathComponent, isDirectory: true)
        let all = (try? fm.contentsOfDirectory(at: authorDir, includingPropertiesForKeys: nil, options: [])) ?? []
        for file in all {
            let name = file.lastPathComponent
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                // Placeholder — can't move content that isn't local yet.
                let realName = String(name.dropFirst().dropLast(".icloud".count))
                if realName.lowercased().hasSuffix(".epub") {
                    result.pendingDownloads.append(authorDir.appendingPathComponent(realName))
                }
                continue
            }
            guard file.pathExtension.lowercased() == "epub" else { continue }
            let dest = destDir.appendingPathComponent(name)
            do {
                if fm.fileExists(atPath: dest.path) {
                    // Same fic exists in the new spot — keep the source copy
                    // in Backups rather than deleting anything.
                    try backUpDuplicate(file, provider: provider, author: authorDir.lastPathComponent, root: root)
                } else {
                    try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                    try fm.moveItem(at: file, to: dest)
                    result.movedEPUBs += 1
                }
            } catch {}
        }
        pruneIfEmpty(authorDir)
    }

    private static func backUpDuplicate(_ file: URL, provider: String, author: String, root: URL) throws {
        let fm = FileManager.default
        let dir = root
            .appendingPathComponent(Organizer.backupsFolder, isDirectory: true)
            .appendingPathComponent(provider, isDirectory: true)
            .appendingPathComponent(author, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let base = file.deletingPathExtension().lastPathComponent
        var dest = dir.appendingPathComponent("\(base) (migrated).epub")
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            dest = dir.appendingPathComponent("\(base) (migrated \(n)).epub")
            n += 1
        }
        try fm.moveItem(at: file, to: dest)
    }

    /// File-level merge of an old Backups tree into `<root>/Backups`.
    /// Legacy author-level paths (`Backups/<Author>/x`) are refiled under
    /// ao3/; provider-level paths are kept as they are.
    private static func mergeBackups(_ oldBackups: URL, into root: URL, result: inout Result) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: oldBackups, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        else { return }
        let newBackups = root.appendingPathComponent(Organizer.backupsFolder, isDirectory: true)
        for case let file as URL in enumerator {
            guard (try? file.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true else { continue }
            var parts = file.path
                .replacingOccurrences(of: oldBackups.path + "/", with: "")
                .components(separatedBy: "/")
            if parts.count == 2 { parts.insert(Organizer.ao3, at: 0) }
            var dest = newBackups
            for dir in parts.dropLast() { dest.appendPathComponent(dir, isDirectory: true) }
            try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
            var target = dest.appendingPathComponent(parts.last!)
            var n = 2
            while fm.fileExists(atPath: target.path) {
                let base = (parts.last! as NSString).deletingPathExtension
                let ext = (parts.last! as NSString).pathExtension
                target = dest.appendingPathComponent("\(base) (\(n))" + (ext.isEmpty ? "" : ".\(ext)"))
                n += 1
            }
            try? fm.moveItem(at: file, to: target)
        }
        pruneTree(oldBackups)
    }

    /// Parses one Author/Title-per-line Favorites.txt.
    private static func favoriteLines(of file: URL) -> [String] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Parks a merged store file in Backups/ instead of deleting it.
    private static func retire(_ file: URL, root: URL) throws {
        let fm = FileManager.default
        let dir = root.appendingPathComponent(Organizer.backupsFolder, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let base = file.deletingPathExtension().lastPathComponent
        let ext = file.pathExtension
        var dest = dir.appendingPathComponent("\(base) (migrated).\(ext)")
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            dest = dir.appendingPathComponent("\(base) (migrated \(n)).\(ext)")
            n += 1
        }
        try fm.moveItem(at: file, to: dest)
    }

    private static func pruneIfEmpty(_ dir: URL) {
        let fm = FileManager.default
        if let left = try? fm.contentsOfDirectory(atPath: dir.path),
           left.filter({ $0 != ".DS_Store" }).isEmpty {
            try? fm.removeItem(at: dir)
        }
    }

    /// Removes empty directories bottom-up after a Backups merge.
    private static func pruneTree(_ dir: URL) {
        for sub in subdirectories(of: dir) { pruneTree(sub) }
        pruneIfEmpty(dir)
    }

    /// True when a store holds nothing (or only empty folders / .DS_Store),
    /// so the caller can remove the folder itself.
    public static func isEffectivelyEmpty(_ dir: URL) -> Bool {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [])
        else { return false }
        for case let entry as URL in enumerator {
            if entry.lastPathComponent == ".DS_Store" { continue }
            if (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { continue }
            return false
        }
        return true
    }
}

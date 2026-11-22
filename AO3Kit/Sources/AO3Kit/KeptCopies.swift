import Foundation

/// A copy of a fic Parade kept instead of losing it: a version an update
/// replaced (in `Backups/`) or a deleted fic (in `Trash/`).
public struct KeptCopy: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable { case backup, trash }

    public let kind: Kind
    /// The library it belongs to: the library root, or its `To Read` folder.
    /// A restore puts it back there.
    public let root: URL
    public let provider: String
    public let author: String
    public let title: String
    /// When it was kept: the stamp in its name.
    public let date: Date
    /// Bytes, when the file system knows (a ".icloud" placeholder doesn't).
    public let size: Int?
    /// False while it's an undownloaded ".….icloud" placeholder.
    public let isDownloaded: Bool
    /// The real file location, even while iCloud only has a placeholder.
    public let url: URL

    public var id: String { url.path }

    /// Where it goes back to: `<root>/<provider>/<author>/<title>.epub`.
    public var home: URL {
        root.appendingPathComponent(provider, isDirectory: true)
            .appendingPathComponent(author, isDirectory: true)
            .appendingPathComponent(title).appendingPathExtension("epub")
    }

    /// True when it came from the To Read list rather than the library.
    public var isToRead: Bool { root.lastPathComponent == Organizer.toReadFolder }
}

/// The two kept-copies folders, `Backups/` and `Trash/`, each laid out as
/// `<folder>/<provider>/<Author>/<Title> (<yyyy-MM-dd HHmmss>).epub` in the
/// library root and again in `To Read/` for To Read fics. Both live in the
/// library folder, so they sync through iCloud with it: an update or a
/// delete on one device reaches every device, and so does the copy it kept.
/// The library scan skips both folders.
///
/// Copies are kept for `retention` (about a month), then `prune` removes
/// them, except a backup that is bigger than the fic now in the library:
/// that one may hold chapters a bad download lost, so it stays.
public enum KeptCopies {
    /// How long a copy is kept: about a month.
    public static let retention: TimeInterval = 30 * 86_400

    /// The stamp `Organizer.backUp` writes into names, in local time.
    static let stampFormat = "yyyy-MM-dd HHmmss"

    /// `<title> (<stamp>)`, or `<title> (<stamp>) <n>` when two landed in
    /// the same second.
    private static let namePattern = try! NSRegularExpression(
        pattern: #"^(.*) \((\d{4}-\d{2}-\d{2} \d{6})\)(?: \d+)?\.epub$"#)

    static func stampFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = stampFormat
        return formatter
    }

    static func folderName(_ kind: KeptCopy.Kind) -> String {
        kind == .backup ? Organizer.backupsFolder : Organizer.trashFolder
    }

    /// The library root and its To Read folder: each has its own Backups
    /// and Trash.
    private static func roots(_ root: URL) -> [URL] {
        [root, root.appendingPathComponent(Organizer.toReadFolder, isDirectory: true)]
    }

    /// The title and date in a kept copy's file name, or nil for a file
    /// Parade doesn't manage here (a "(migrated)" duplicate, a retired
    /// Favorites.txt). A ".Name.epub.icloud" placeholder parses as its file.
    static func parse(_ fileName: String,
                      formatter: DateFormatter = stampFormatter()) -> (title: String, date: Date)? {
        let name = realName(fileName) ?? fileName
        let range = NSRange(name.startIndex..., in: name)
        guard let match = namePattern.firstMatch(in: name, range: range),
              let title = Range(match.range(at: 1), in: name),
              let stamp = Range(match.range(at: 2), in: name),
              let date = formatter.date(from: String(name[stamp]))
        else { return nil }
        return (String(name[title]), date)
    }

    /// "Name.epub" for an iCloud placeholder ".Name.epub.icloud".
    private static func realName(_ fileName: String) -> String? {
        guard fileName.hasPrefix("."), fileName.hasSuffix(".icloud") else { return nil }
        return String(fileName.dropFirst().dropLast(".icloud".count))
    }

    private static func fileSize(_ url: URL) -> Int? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }

    // MARK: - listing

    /// Every kept copy of `kind`, in the library and To Read, newest first.
    /// Reads folder listings and sizes; opens no files.
    public static func list(_ kind: KeptCopy.Kind, root: URL) -> [KeptCopy] {
        let fm = FileManager.default
        let formatter = stampFormatter()
        var found: [KeptCopy] = []
        for libraryRoot in roots(root) {
            let folder = libraryRoot.appendingPathComponent(folderName(kind), isDirectory: true)
            for provider in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] where !provider.hasPrefix(".") {
                let providerDir = folder.appendingPathComponent(provider, isDirectory: true)
                for author in (try? fm.contentsOfDirectory(atPath: providerDir.path)) ?? [] where !author.hasPrefix(".") {
                    let dir = providerDir.appendingPathComponent(author, isDirectory: true)
                    for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] {
                        guard let parsed = parse(name, formatter: formatter) else { continue }
                        let placeholder = realName(name)
                        let url = dir.appendingPathComponent(placeholder ?? name)
                        found.append(KeptCopy(
                            kind: kind, root: libraryRoot, provider: provider, author: author,
                            title: parsed.title, date: parsed.date,
                            size: placeholder == nil ? fileSize(url) : nil,
                            isDownloaded: placeholder == nil, url: url))
                    }
                }
            }
        }
        return found.sorted { $0.date > $1.date }
    }

    /// The backups of one fic (`<libraryRoot>/<provider>/<author>/<title>.epub`),
    /// newest first. Reads one folder.
    public static func backups(libraryRoot: URL, provider: String, author: String, title: String) -> [KeptCopy] {
        let dir = libraryRoot
            .appendingPathComponent(Organizer.backupsFolder, isDirectory: true)
            .appendingPathComponent(provider, isDirectory: true)
            .appendingPathComponent(author, isDirectory: true)
        let formatter = stampFormatter()
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .compactMap { name -> KeptCopy? in
                guard let parsed = parse(name, formatter: formatter), parsed.title == title else { return nil }
                let placeholder = realName(name)
                let url = dir.appendingPathComponent(placeholder ?? name)
                return KeptCopy(kind: .backup, root: libraryRoot, provider: provider, author: author,
                                title: title, date: parsed.date,
                                size: placeholder == nil ? fileSize(url) : nil,
                                isDownloaded: placeholder == nil, url: url)
            }
            .sorted { $0.date > $1.date }
    }

    // MARK: - trash and restore

    /// Moves a fic's EPUB from `<libraryRoot>/<provider>/<Author>/` to
    /// `<libraryRoot>/Trash/<provider>/<Author>/<Title> (<stamp>).epub`.
    /// A fic iCloud hasn't downloaded here moves as its placeholder.
    @discardableResult
    public static func trash(_ file: URL, libraryRoot: URL, provider: String, now: Date = Date()) throws -> URL {
        let fm = FileManager.default
        let dir = libraryRoot
            .appendingPathComponent(Organizer.trashFolder, isDirectory: true)
            .appendingPathComponent(provider, isDirectory: true)
            .appendingPathComponent(file.deletingLastPathComponent().lastPathComponent, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let base = file.deletingPathExtension().lastPathComponent + " (\(stampFormatter().string(from: now)))"
        var name = base + ".epub"
        var n = 2
        while fm.fileExists(atPath: dir.appendingPathComponent(name).path)
                || fm.fileExists(atPath: dir.appendingPathComponent("." + name + ".icloud").path) {
            name = base + " \(n).epub"
            n += 1
        }
        let placeholder = file.deletingLastPathComponent()
            .appendingPathComponent("." + file.lastPathComponent + ".icloud")
        if !fm.fileExists(atPath: file.path), fm.fileExists(atPath: placeholder.path) {
            try fm.moveItem(at: placeholder, to: dir.appendingPathComponent("." + name + ".icloud"))
        } else {
            try fm.moveItem(at: file, to: dir.appendingPathComponent(name))
        }
        return dir.appendingPathComponent(name)
    }

    /// Puts `copy` back where it came from, in the library or To Read. A
    /// fic there now is backed up first, so a restore can itself be undone;
    /// a restored version keeps the fic's "added" date. The copy has to be
    /// downloaded. Returns where it went.
    @discardableResult
    public static func restore(_ copy: KeptCopy) throws -> URL {
        let fm = FileManager.default
        guard copy.isDownloaded, fm.fileExists(atPath: copy.url.path) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: copy.url.path])
        }
        let home = copy.home
        var added: Date?
        if fm.fileExists(atPath: home.path) {
            added = (try? home.resourceValues(forKeys: [.creationDateKey]))?.creationDate
            try Organizer(root: copy.root, provider: copy.provider).backUp(home)
        } else {
            try fm.createDirectory(at: home.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        try fm.moveItem(at: copy.url, to: home)
        if let added {
            try? fm.setAttributes([.creationDate: added], ofItemAtPath: home.path)
        }
        removeEmptyFolders(from: copy.url.deletingLastPathComponent(),
                           upTo: copy.root.appendingPathComponent(folderName(copy.kind)))
        return home
    }

    // MARK: - pruning

    /// Removes kept copies older than `retention` (by the stamp in their
    /// names) from Backups and Trash, in the library and To Read, and the
    /// folders that leaves empty. Never touches a file without a stamp, or
    /// a backup bigger than the fic in the library now (or whose size it
    /// can't tell): that may be the copy with the chapters a bad download
    /// lost. Walks only those folders and opens no files, so it's cheap
    /// enough for every launch. Returns how many it removed.
    @discardableResult
    public static func prune(root: URL, olderThan retention: TimeInterval = retention,
                             now: Date = Date()) -> Int {
        let cutoff = now.addingTimeInterval(-retention)
        var removed = 0
        for copy in list(.backup, root: root) + list(.trash, root: root) where copy.date < cutoff {
            if copy.kind == .backup, !outgrown(copy) { continue }
            let fm = FileManager.default
            let target = copy.isDownloaded
                ? copy.url
                : copy.url.deletingLastPathComponent().appendingPathComponent("." + copy.url.lastPathComponent + ".icloud")
            if (try? fm.removeItem(at: target)) != nil {
                removed += 1
                removeEmptyFolders(from: copy.url.deletingLastPathComponent(),
                                   upTo: copy.root.appendingPathComponent(folderName(copy.kind)))
            }
        }
        return removed
    }

    /// True when the fic in the library now is at least as big as this
    /// backup, so the backup holds nothing the fic lacks. A fic that's gone
    /// from its old place (renamed by a relink, or deleted to Trash) leaves
    /// its backups to the date rule alone.
    static func outgrown(_ backup: KeptCopy) -> Bool {
        let home = backup.home
        let fm = FileManager.default
        guard fm.fileExists(atPath: home.path) else {
            let placeholder = home.deletingLastPathComponent().appendingPathComponent("." + home.lastPathComponent + ".icloud")
            // Only a placeholder: its size is unknown, so keep the backup.
            return !fm.fileExists(atPath: placeholder.path)
        }
        guard let backupSize = backup.size, let current = fileSize(home) else { return false }
        return backupSize <= current
    }

    /// Removes `dir` and its parents while they're empty, stopping at `top`.
    private static func removeEmptyFolders(from dir: URL, upTo top: URL) {
        let fm = FileManager.default
        var dir = dir.standardizedFileURL
        let stop = top.standardizedFileURL.path
        while dir.path.hasPrefix(stop + "/") {
            guard let left = try? fm.contentsOfDirectory(atPath: dir.path),
                  left.allSatisfy({ $0 == ".DS_Store" }) else { return }
            try? fm.removeItem(at: dir)
            dir = dir.deletingLastPathComponent()
        }
    }
}

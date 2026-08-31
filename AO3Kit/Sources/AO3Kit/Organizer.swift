import Foundation

/// Files downloaded EPUBs into `<root>/<provider>/<Author>/<Title>.epub`.
/// The provider folder ("ao3" today) keeps sources separate so the same
/// library root can hold other archives later.
public struct Organizer: Sendable {
    public let root: URL
    public let provider: String

    /// The provider folder for AO3 downloads.
    public static let ao3 = "ao3"

    public init(root: URL, provider: String = Organizer.ao3) {
        self.root = root
        self.provider = provider
    }

    /// Library subfolder that holds superseded versions; never a provider.
    public static let backupsFolder = "Backups"

    /// Moves `epubFile` into place for `work`. A previous version at the same
    /// path (same fic, newer text) is moved into Backups/ first, never
    /// deleted. Returns the final location.
    @discardableResult
    public func place(_ epubFile: URL, for work: WorkInfo) throws -> URL {
        let authorDir = root
            .appendingPathComponent(provider, isDirectory: true)
            .appendingPathComponent(Self.sanitize(work.authorLabel), isDirectory: true)
        try FileManager.default.createDirectory(at: authorDir, withIntermediateDirectories: true)
        let dest = authorDir
            .appendingPathComponent(Self.sanitize(work.title))
            .appendingPathExtension("epub")
        if FileManager.default.fileExists(atPath: dest.path) {
            try backUp(dest)
        }
        try FileManager.default.moveItem(at: epubFile, to: dest)
        return dest
    }

    /// Moves a superseded EPUB to `Backups/<provider>/<Author>/<Title> (<stamp>).epub`.
    private func backUp(_ file: URL) throws {
        let fm = FileManager.default
        let author = file.deletingLastPathComponent().lastPathComponent
        let dir = root
            .appendingPathComponent(Self.backupsFolder, isDirectory: true)
            .appendingPathComponent(provider, isDirectory: true)
            .appendingPathComponent(author, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        let stamp = formatter.string(from: Date())
        let base = file.deletingPathExtension().lastPathComponent
        var dest = dir.appendingPathComponent("\(base) (\(stamp)).epub")
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            dest = dir.appendingPathComponent("\(base) (\(stamp)) \(n).epub")
            n += 1
        }
        try fm.moveItem(at: file, to: dest)
    }

    /// Makes a string safe as an APFS/iCloud Drive file or folder name.
    public static func sanitize(_ name: String) -> String {
        var s = name
        s = s.replacingOccurrences(of: "/", with: "-")
        s = s.replacingOccurrences(of: ":", with: "-")
        s = s.replacingOccurrences(of: "\\", with: "-")
        s = s.components(separatedBy: .controlCharacters).joined()
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespaces)
        while s.hasPrefix(".") { s.removeFirst() }  // no hidden files
        if s.count > 120 { s = String(s.prefix(120)).trimmingCharacters(in: .whitespaces) }
        return s.isEmpty ? "Untitled" : s
    }
}

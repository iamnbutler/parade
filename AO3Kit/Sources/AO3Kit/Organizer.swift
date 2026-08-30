import Foundation

/// Files downloaded EPUBs into `<root>/<Author>/<Title>.epub`.
public struct Organizer: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// Moves `epubFile` into place for `work`, overwriting any previous
    /// version (same fic, newer text). Returns the final location.
    @discardableResult
    public func place(_ epubFile: URL, for work: WorkInfo) throws -> URL {
        let authorDir = root.appendingPathComponent(Self.sanitize(work.authorLabel), isDirectory: true)
        try FileManager.default.createDirectory(at: authorDir, withIntermediateDirectories: true)
        let dest = authorDir
            .appendingPathComponent(Self.sanitize(work.title))
            .appendingPathExtension("epub")
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: epubFile, to: dest)
        return dest
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

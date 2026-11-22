import Foundation
import ZIPFoundation

/// Keeps a download that's missing chapters from replacing a saved copy:
/// the new EPUB must have at least as many chapters as the copy it
/// replaces, and as the work page says are posted.
public enum ChapterGuard {

    /// Throws `AO3Error.missingChapters` when `newEPUB` has fewer chapters
    /// than `saved` (an EPUB already there, if it is and can be read) or
    /// than `stated`. A count that can't be read is left out, never guessed.
    public static func check(_ newEPUB: URL, replacing saved: URL?, stated: Int?) throws {
        guard let got = chapterCount(epubAt: newEPUB) else { return }
        let savedCount = saved
            .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            .flatMap(chapterCount(epubAt:))
        if let problem = shortfall(got: got, saved: savedCount, stated: stated) { throw problem }
    }

    /// The error for `got` chapters against the saved copy's count and the
    /// stated one, or nil when there are enough. Pure.
    static func shortfall(got: Int, saved: Int?, stated: Int?) -> AO3Error? {
        let expected = max(saved ?? 0, stated ?? 0)
        guard got < expected else { return nil }
        return .missingChapters(got: got, expected: expected, keptSaved: saved != nil)
    }

    /// Chapters in an EPUB, from its table of contents (toc.ncx): every
    /// entry but the preface and afterword, as AO3's export and Parade's own
    /// EPUBs lay it out. nil when there's no table of contents to read.
    public static func chapterCount(epubAt url: URL) -> Int? {
        guard let archive = try? Archive(url: url, accessMode: .read),
              let entry = archive.first(where: { $0.path.lowercased().hasSuffix(".ncx") })
        else { return nil }
        var data = Data()
        guard (try? archive.extract(entry, skipCRC32: true, consumer: { data.append($0) })) != nil else { return nil }
        return chapterCount(ncx: String(decoding: data, as: UTF8.self))
    }

    /// Pure: counts the navPoints whose label isn't Preface or Afterword.
    static func chapterCount(ncx: String) -> Int? {
        guard let navMap = HTMLExtract.firstMatch(in: ncx, pattern: #"<navMap>([\s\S]*?)</navMap>"#) else { return nil }
        let labels = HTMLExtract.allMatches(
            in: navMap, pattern: #"<navPoint\b[^>]*>\s*<navLabel>\s*<text>([\s\S]*?)</text>"#)
            .map { HTMLExtract.decodeEntities($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !labels.isEmpty else { return nil }
        return labels.filter { $0 != "Preface" && $0 != "Afterword" }.count
    }
}

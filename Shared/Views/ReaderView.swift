import SwiftUI
import AO3Kit

/// Reads a fic: its EPUB's text, chapter after chapter, on one scrolling
/// page set in the book's type. A full-screen cover on iOS, its own window
/// on the Mac.
struct ReaderView: View {
    let item: LibraryItem
    @State private var book: EPUBBook?
    @State private var failure: String?

    var body: some View {
        Group {
            if let book {
                ReaderPage(item: item, book: book)
            } else if let failure {
                EmptyPage(title: "This fic won't open", message: failure)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .leatherBackground()
        .task(id: item.id + String(item.date.timeIntervalSince1970)) {
            await load()
        }
    }

    private func load() async {
        guard item.isDownloaded else {
            failure = "It's still downloading from iCloud. Try again in a moment."
            return
        }
        let url = item.url
        do {
            // Unzipping and parsing a long fic takes a moment; keep it off
            // the main thread.
            book = try await Task.detached(priority: .userInitiated) {
                try EPUBBookParser.parse(epubAt: url)
            }.value
        } catch {
            failure = "Parade couldn't read the EPUB. Updating the fic from AO3 downloads a fresh copy."
        }
    }
}

/// The text itself. Every block of every chapter is one lazy row, so a
/// 300,000-word fic only lays out what's on screen.
private struct ReaderPage: View {
    let item: LibraryItem
    let book: EPUBBook
    @Environment(\.palette) private var palette

    /// One row of the page.
    private struct Line: Identifiable {
        let id: Int
        let block: EPUBBook.Block
        /// The first block of a later section: give it room to breathe.
        let opensSection: Bool
    }

    private var lines: [Line] {
        var out: [Line] = []
        for (s, section) in book.sections.enumerated() {
            for (b, block) in section.blocks.enumerated() {
                out.append(Line(id: out.count, block: block, opensSection: s > 0 && b == 0))
            }
        }
        return out
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(lines) { line in
                    BlockView(block: line.block)
                        .padding(.top, line.opensSection ? 56 : 0)
                }
                Fleuron()
                    .padding(.vertical, 48)
            }
            .textSelection(.enabled)
            .frame(maxWidth: Reading.measure, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
        }
    }
}

/// Reading layout shared by the page's parts.
private enum Reading {
    /// Line length: about 65–75 characters of Newsreader at body size.
    static let measure: CGFloat = 640
    static let paragraphSpacing: CGFloat = 14
    static let quoteIndent: CGFloat = 18
}

private struct BlockView: View {
    let block: EPUBBook.Block
    @Environment(\.palette) private var palette

    var body: some View {
        switch block.kind {
        case .rule:
            Fleuron()
                .padding(.vertical, 20)
        case .heading(let level):
            Text(styled(block.runs))
                .textRole(level <= 1 ? .title : .heading)
                .padding(.top, level <= 2 ? 8 : 4)
                .padding(.bottom, level <= 2 ? 22 : 12)
                .fixedSize(horizontal: false, vertical: true)
        case .paragraph where Self.isLabel(block):
            // AO3's "Summary", "Notes", "End Notes": book furniture.
            Text(block.text)
                .textRole(.kicker)
                .padding(.top, 10)
                .padding(.bottom, 6)
        case .paragraph:
            Text(styled(block.runs))
                .textRole(block.quoteDepth > 0 ? .dek : .body)
                .fixedSize(horizontal: false, vertical: true)
                // Spacing inside the quote's rule, so consecutive quoted
                // paragraphs share one unbroken line.
                .padding(.bottom, block.quoteDepth > 0 ? Reading.paragraphSpacing : 0)
                .padding(.leading, block.quoteDepth > 0 ? 14 : 0)
                .overlay(alignment: .leading) {
                    if block.quoteDepth > 0 {
                        // Author's notes and summaries sit behind a gold rule.
                        Rectangle()
                            .fill(palette.goldFaint)
                            .frame(width: 1)
                    }
                }
                .padding(.leading, CGFloat(max(0, block.quoteDepth - 1)) * Reading.quoteIndent)
                .padding(.bottom, block.quoteDepth > 0 ? 0 : Reading.paragraphSpacing)
        }
    }

    private static let labels: Set<String> = [
        "summary", "notes", "end notes", "chapter summary", "chapter notes", "chapter end notes",
    ]

    /// A lone label line AO3 puts before a quoted summary or notes block.
    static func isLabel(_ block: EPUBBook.Block) -> Bool {
        block.quoteDepth == 0 && labels.contains(block.text.lowercased().trimmingCharacters(in: .punctuationCharacters))
    }

    /// Runs as one attributed string: italic and bold through presentation
    /// intents, so they pick the reading face's own italic and semibold.
    private func styled(_ runs: [EPUBBook.Run]) -> AttributedString {
        var out = AttributedString()
        for run in runs {
            var piece = AttributedString(run.text)
            var intent: InlinePresentationIntent = []
            if run.italic { intent.insert(.emphasized) }
            if run.bold { intent.insert(.stronglyEmphasized) }
            if !intent.isEmpty { piece.inlinePresentationIntent = intent }
            if run.underline { piece.underlineStyle = .single }
            if let link = run.link {
                piece.link = link
                piece.foregroundColor = palette.rose
            }
            out.append(piece)
        }
        return out
    }
}

#if os(macOS)
/// The Mac's reader window, opened with the fic's id.
struct ReaderWindow: View {
    let id: String?
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if let id, let item = model.item(withID: id) {
                ReaderView(item: item)
                    .navigationTitle(item.title)
            } else {
                EmptyPage(title: "This fic isn't in your library", message: "It may have been deleted or moved.")
                    .leatherBackground()
            }
        }
        .frame(minWidth: 420, minHeight: 360)
    }
}
#endif

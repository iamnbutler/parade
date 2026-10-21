import SwiftUI
import AO3Kit

/// Reads a fic: its EPUB's text, chapter after chapter, on one scrolling
/// page set in the book's type. Remembers where you were, jumps between
/// chapters, and lets the reader pick text size and page color. Full screen
/// on iOS; it takes over the main window on the Mac.
struct ReaderView: View {
    let item: LibraryItem
    @EnvironmentObject private var model: AppModel
    @State private var book: EPUBBook?
    @State private var failure: String?
    /// Where this fic was left off, read once when it opens.
    @State private var start: ReadingPosition?
    @AppStorage("reader.textSize.v1") private var textSize = ReaderTextSize.standard.rawValue
    @AppStorage("reader.paper.v1") private var paperRaw = ReaderPaper.leather.rawValue
    @State private var showContents = false
    @State private var showType = false
    /// Set to scroll the page to a section — a chapter picked from the
    /// contents.
    @State private var jump: Int?

    private var paper: ReaderPaper { ReaderPaper(rawValue: paperRaw) ?? .leather }
    private var size: ReaderTextSize { ReaderTextSize(rawValue: textSize) ?? .standard }

    var body: some View {
        Group {
            if let book {
                ReaderPage(
                    book: book,
                    scale: size.scale,
                    start: start,
                    jump: $jump,
                    onPosition: { model.saveReadingPosition($0, for: item) })
            } else if let failure {
                EmptyPage(title: "This fic won't open", message: failure)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .leatherBackground()
        .palette(paper.palette)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showContents = true
                } label: {
                    Label("Contents", systemImage: "list.bullet")
                }
                .help("Chapters")
                .disabled(book == nil)
                .popover(isPresented: $showContents, arrowEdge: .bottom) {
                    if let book {
                        ContentsList(book: book) { section in
                            jump = section
                            showContents = false
                        }
                        .palette(paper.palette)
                    }
                }
                Button {
                    showType = true
                } label: {
                    Label("Text", systemImage: "textformat.size")
                }
                .help("Text size and page color")
                .popover(isPresented: $showType, arrowEdge: .bottom) {
                    TypeControls(textSize: $textSize, paperRaw: $paperRaw)
                        .palette(paper.palette)
                }
            }
        }
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
        start = model.readingPosition(for: item)
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

// MARK: - reading settings

/// Text sizes, as steps rather than a slider: each a scale on the reading
/// type.
enum ReaderTextSize: Int, CaseIterable {
    case smaller = -1, standard = 0, larger = 1, large = 2, largest = 3

    var scale: CGFloat { [0.9, 1, 1.12, 1.25, 1.4][rawValue + 1] }
}

/// The page under the text.
enum ReaderPaper: String, CaseIterable, Identifiable {
    case leather, noir, paper
    var id: String { rawValue }

    var palette: Palette {
        switch self {
        case .leather: .leather
        case .noir: .noir
        case .paper: .paper
        }
    }

    var label: String {
        switch self {
        case .leather: "Leather"
        case .noir: "Noir"
        case .paper: "Paper"
        }
    }
}

/// Reading layout: the reading type at the chosen size.
private struct ReadingType {
    let scale: CGFloat

    /// Line length: about 65–75 characters of Newsreader at body size.
    var measure: CGFloat { 640 * min(scale, 1.15) }
    var body: Font { .reading(18 * scale, relativeTo: .body) }
    var quote: Font { .reading(17 * scale, relativeTo: .body, italic: true) }
    var heading: Font { .display(26 * scale, relativeTo: .title2) }
    var title: Font { .display(32 * scale, relativeTo: .title) }
    var label: Font { .display(19 * scale, relativeTo: .subheadline, italic: true) }
    /// Book-like leading: about 1.75 for body text.
    var lineSpacing: CGFloat { 13 * scale }
    var paragraphSpacing: CGFloat { 22 * scale }
    let quoteIndent: CGFloat = 18
}

// MARK: - the page

/// The text itself. Every block of every chapter is one lazy row, so a
/// 300,000-word fic only lays out what's on screen.
private struct ReaderPage: View {
    let book: EPUBBook
    let scale: CGFloat
    /// Where to open.
    let start: ReadingPosition?
    @Binding var jump: Int?
    let onPosition: (ReadingPosition) -> Void
    @State private var topLine: Int?
    @State private var restored = false

    /// One row of the page.
    private struct Line: Identifiable {
        let id: Int
        let block: EPUBBook.Block
        let section: Int
        let indexInSection: Int
    }

    private var lines: [Line] {
        var out: [Line] = []
        for (s, section) in book.sections.enumerated() {
            for (b, block) in section.blocks.enumerated() {
                // A "Notes" label whose notes didn't come through (AO3 often
                // just links to the end of the work) would stand alone.
                if BlockView.isLabel(block), !(section.blocks.indices.contains(b + 1) && section.blocks[b + 1].quoteDepth > 0) {
                    continue
                }
                out.append(Line(id: out.count, block: block, section: s, indexInSection: b))
            }
        }
        return out
    }

    var body: some View {
        let lines = lines
        let type = ReadingType(scale: scale)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { line in
                        BlockView(block: line.block, type: type)
                            .padding(.top, line.section > 0 && line.indexInSection == 0 ? 64 * scale : 0)
                            .id(line.id)
                    }
                    Fleuron()
                        .padding(.vertical, 48)
                }
                .scrollTargetLayout()
                .textSelection(.enabled)
                .frame(maxWidth: type.measure, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)
            }
            .scrollPosition(id: $topLine, anchor: .top)
            .onAppear {
                guard !restored else { return }
                restored = true
                if let start, let line = lines.first(where: { $0.section == start.section && $0.indexInSection >= start.block }) {
                    // After first layout, or the lazy stack ignores the jump.
                    DispatchQueue.main.async { proxy.scrollTo(line.id, anchor: .top) }
                }
            }
            .onChange(of: jump) { _, section in
                guard let section else { return }
                if let line = lines.first(where: { $0.section >= section }) {
                    withAnimation(.snappy) { proxy.scrollTo(line.id, anchor: .top) }
                }
                jump = nil
            }
            // Save the place once scrolling settles, not on every frame.
            .task(id: topLine) {
                guard let id = topLine, id < lines.count else { return }
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                onPosition(ReadingPosition(section: lines[id].section, block: lines[id].indexInSection))
            }
        }
    }
}

private struct BlockView: View {
    let block: EPUBBook.Block
    let type: ReadingType
    @Environment(\.palette) private var palette

    var body: some View {
        switch block.kind {
        case .rule:
            Fleuron()
                .padding(.vertical, 22)
        case .heading(let level):
            Text(styled(block.runs))
                .font(level <= 1 ? type.title : type.heading)
                .foregroundStyle(palette.ink)
                .lineSpacing(2)
                .padding(.top, 8)
                .padding(.bottom, level <= 2 ? 26 : 14)
                .fixedSize(horizontal: false, vertical: true)
        case .paragraph where Self.isLabel(block):
            // AO3's "Summary", "Notes", "End Notes": book furniture.
            Text(block.text)
                .font(type.label)
                .foregroundStyle(palette.gold)
                .padding(.top, 10)
                .padding(.bottom, 8)
        case .paragraph:
            let quoted = block.quoteDepth > 0
            Text(styled(block.runs))
                .font(quoted ? type.quote : type.body)
                .foregroundStyle(quoted ? palette.inkSoft : palette.ink)
                .lineSpacing(quoted ? type.lineSpacing * 0.8 : type.lineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                // Spacing inside the quote's rule, so consecutive quoted
                // paragraphs share one unbroken line.
                .padding(.bottom, quoted ? type.paragraphSpacing * 0.8 : 0)
                .padding(.leading, quoted ? 14 : 0)
                .overlay(alignment: .leading) {
                    if quoted {
                        // Author's notes and summaries sit behind a gold rule.
                        Rectangle()
                            .fill(palette.goldFaint)
                            .frame(width: 1)
                    }
                }
                .padding(.leading, CGFloat(max(0, block.quoteDepth - 1)) * type.quoteIndent)
                .padding(.bottom, quoted ? 0 : type.paragraphSpacing)
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

// MARK: - contents and type controls

/// The chapters, to jump between.
private struct ContentsList: View {
    let book: EPUBBook
    let jump: (Int) -> Void
    @Environment(\.palette) private var palette

    private struct Entry: Identifiable {
        let id: Int  // the section's index
        let title: String
    }

    private var entries: [Entry] {
        book.sections.enumerated().map { i, section in
            let heading = section.blocks.first { if case .heading = $0.kind { return true } else { return false } }
            return Entry(id: i, title: section.title ?? heading?.text ?? "Section \(i + 1)")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Text("Contents")
                    .textRole(.kicker)
                    .padding(.bottom, 8)
                ForEach(entries) { entry in
                    Button {
                        jump(entry.id)
                    } label: {
                        Text(entry.title)
                            .font(.reading(16, relativeTo: .body))
                            .foregroundStyle(palette.ink)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 260, idealWidth: 300, maxHeight: 460)
        .background { LeatherBackground() }
        .presentationCompactAdaptation(.popover)
    }
}

/// Text size steps and page color.
private struct TypeControls: View {
    @Binding var textSize: Int
    @Binding var paperRaw: String
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Text").textRole(.kicker)
            HStack(spacing: 10) {
                Button {
                    textSize = max(ReaderTextSize.smaller.rawValue, textSize - 1)
                } label: {
                    Text("A").font(.display(16))
                        .frame(width: 44, height: 32)
                }
                .buttonStyle(.leather)
                .disabled(textSize <= ReaderTextSize.smaller.rawValue)
                .accessibilityLabel("Smaller text")
                Button {
                    textSize = min(ReaderTextSize.largest.rawValue, textSize + 1)
                } label: {
                    Text("A").font(.display(24))
                        .frame(width: 44, height: 32)
                }
                .buttonStyle(.leather)
                .disabled(textSize >= ReaderTextSize.largest.rawValue)
                .accessibilityLabel("Larger text")
            }
            Text("Page").textRole(.kicker)
            HStack(spacing: 12) {
                ForEach(ReaderPaper.allCases) { paper in
                    Button {
                        paperRaw = paper.rawValue
                    } label: {
                        VStack(spacing: 6) {
                            Circle()
                                .fill(paper.palette.leather)
                                .overlay(Circle().strokeBorder(
                                    paperRaw == paper.rawValue ? palette.gold : palette.rule,
                                    lineWidth: paperRaw == paper.rawValue ? 2 : 1))
                                .frame(width: 34, height: 34)
                            Text(paper.label)
                                .font(.reading(13, relativeTo: .caption))
                                .foregroundStyle(palette.inkSoft)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(paperRaw == paper.rawValue ? .isSelected : [])
                }
            }
        }
        .padding(20)
        .background { LeatherBackground() }
        .presentationCompactAdaptation(.popover)
    }
}

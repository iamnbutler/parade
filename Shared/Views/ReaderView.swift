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
    @AppStorage("reader.mode.v1") private var modeRaw = ReaderMode.pages.rawValue
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
                if ReaderMode(rawValue: modeRaw) == .scroll {
                    ReaderPage(
                        book: book,
                        scale: size.scale,
                        start: start,
                        jump: $jump,
                        onPosition: { model.saveReadingPosition($0, for: item) })
                } else {
                    PagedReader(
                        book: book,
                        scale: size.scale,
                        start: start,
                        jump: $jump,
                        onPosition: { model.saveReadingPosition($0, for: item) })
                }
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
                    TypeControls(textSize: $textSize, paperRaw: $paperRaw, modeRaw: $modeRaw)
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
struct ReadingType {
    let scale: CGFloat

    /// Line length: about 65–75 characters of Newsreader at body size.
    var measure: CGFloat { 640 * min(scale, 1.15) }
    var body: Font { .reading(18 * scale, relativeTo: .body) }
    var quote: Font { .reading(17 * scale, relativeTo: .body, italic: true) }
    var heading: Font { .display(26 * scale, relativeTo: .title2) }
    var title: Font { .display(32 * scale, relativeTo: .title) }
    var label: Font { .display(19 * scale, relativeTo: .subheadline, italic: true) }
    var numeral: Font { .display(26 * scale, relativeTo: .title2) }
    var chapterTitle: Font { .display(30 * scale, relativeTo: .title2, italic: true) }
    var headingLeading: CGFloat { 4 * scale }
    /// Book-like leading: about 1.75 for body text.
    var lineSpacing: CGFloat { 13 * scale }
    var paragraphSpacing: CGFloat { 22 * scale }
    let quoteIndent: CGFloat = 18
}

// MARK: - the page

/// The text itself. Every block of every chapter is one lazy row, so a
/// 300,000-word fic only lays out what's on screen.
/// The page's rows, shared by the scrolling and paged readers.
private enum ReaderLines {
    /// One row of the page: a block, or a labelled note (AO3's "Summary",
    /// "Notes", "End Notes" with the quoted paragraphs that follow).
    struct Line: Identifiable {
        let id: Int
        let content: Content
        let section: Int
        let indexInSection: Int

        enum Content {
            case block(EPUBBook.Block)
            case note(label: String, blocks: [EPUBBook.Block])
        }
    }

    static func build(_ book: EPUBBook) -> [Line] {
        var out: [Line] = []
        for (s, section) in book.sections.enumerated() {
            let blocks = section.blocks
            var b = 0
            while b < blocks.count {
                let block = blocks[b]
                if BlockView.isLabel(block) {
                    var end = b + 1
                    while end < blocks.count, blocks[end].quoteDepth > 0 { end += 1 }
                    // A label whose notes didn't come through (AO3 often just
                    // links to the end of the work) is dropped.
                    if end > b + 1 {
                        out.append(Line(id: out.count, content: .note(label: block.text, blocks: Array(blocks[(b + 1)..<end])),
                                        section: s, indexInSection: b))
                    }
                    b = end
                    continue
                }
                if !BlockView.isFurniture(block) {
                    out.append(Line(id: out.count, content: .block(block), section: s, indexInSection: b))
                }
                b += 1
            }
        }
        return out
    }

}

private struct ReaderPage: View {
    let book: EPUBBook
    let scale: CGFloat
    /// Where to open.
    let start: ReadingPosition?
    @Binding var jump: Int?
    let onPosition: (ReadingPosition) -> Void
    @State private var topLine: Int?
    @State private var restored = false

    private typealias Line = ReaderLines.Line
    private var lines: [Line] { ReaderLines.build(book) }

    var body: some View {
        let lines = lines
        let type = ReadingType(scale: scale)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { line in
                        Group {
                            switch line.content {
                            case .block(let block): BlockView(block: block, type: type)
                            case .note(let label, let blocks): NoteView(label: label, blocks: blocks, type: type)
                            }
                        }
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

/// A summary in the stitched card; notes on a paper clipping.
private struct NoteView: View {
    let label: String
    let blocks: [EPUBBook.Block]
    let type: ReadingType
    @Environment(\.palette) private var palette

    private var isSummary: Bool { label.lowercased().contains("summary") }

    var body: some View {
        Group {
            if isSummary {
                StitchedCard(label: "The summary") { paragraphs }
            } else {
                PaperClipping(tilt: -0.5) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(label.prefix(1).uppercased() + label.dropFirst().lowercased())
                            .font(type.label)
                            .foregroundStyle(Palette.paper.gold)
                        paragraphs
                    }
                }
                .padding(.horizontal, 6)
            }
        }
        .padding(.vertical, 18 * type.scale)
    }

    private var paragraphs: some View {
        VStack(alignment: .leading, spacing: type.paragraphSpacing * 0.6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                if case .rule = block.kind {
                    Fleuron()
                } else {
                    Text(BlockView(block: block, type: type).styled(block.runs))
                        .font(isSummary ? type.body : type.quote)
                        .lineSpacing(type.lineSpacing * 0.8)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
            if let chapter = Self.chapter(block.text) {
                // "01  The Markings": a gold numeral and the title in gold
                // italic, like a group heading in the book.
                HStack(alignment: .firstTextBaseline, spacing: 14 * type.scale) {
                    Text(String(format: "%02d", chapter.number))
                        .font(type.numeral)
                        .foregroundStyle(palette.gold)
                    Text(chapter.title ?? Self.spelledChapter(chapter.number))
                        .font(type.chapterTitle)
                        .foregroundStyle(palette.gold)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
                .padding(.bottom, 30 * type.scale)
                .accessibilityElement(children: .combine)
            } else {
                Text(styled(block.runs))
                    .font(level <= 1 ? type.title : type.heading)
                    .foregroundStyle(palette.ink)
                    .lineSpacing(type.headingLeading)
                    .padding(.top, 8)
                    .padding(.bottom, level <= 2 ? 22 : 14)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

    /// AO3 wrapper headings that only name the file ("Preface", "Afterword").
    static func isFurniture(_ block: EPUBBook.Block) -> Bool {
        guard case .heading = block.kind else { return false }
        return ["preface", "afterword"].contains(block.text.lowercased())
    }

    /// "Chapter 3: The Fire Within" → (3, "The Fire Within"); "Chapter 17" → (17, nil).
    static func chapter(_ text: String) -> (number: Int, title: String?)? {
        let pattern = #"^\s*Chapter\s+(\d+)\s*(?:[:.\-–—]\s*(.+))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let numRange = Range(m.range(at: 1), in: text), let number = Int(text[numRange])
        else { return nil }
        let title = Range(m.range(at: 2), in: text).map { String(text[$0]).trimmingCharacters(in: .whitespaces) }
        return (number, title?.isEmpty == false ? title : nil)
    }

    /// "Chapter one", for chapters without a title of their own.
    static func spelledChapter(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .spellOut
        return "Chapter " + (f.string(from: NSNumber(value: n)) ?? String(n))
    }

    /// A lone label line AO3 puts before a quoted summary or notes block.
    static func isLabel(_ block: EPUBBook.Block) -> Bool {
        block.quoteDepth == 0 && labels.contains(block.text.lowercased().trimmingCharacters(in: .punctuationCharacters))
    }

    /// Runs as one attributed string: italic and bold through presentation
    /// intents, so they pick the reading face's own italic and semibold.
    func styled(_ runs: [EPUBBook.Run]) -> AttributedString {
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
    @Binding var modeRaw: String
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Layout").textRole(.kicker)
            HStack(spacing: 10) {
                ForEach(ReaderMode.allCases) { mode in
                    Button(mode.label) { modeRaw = mode.rawValue }
                        .buttonStyle(LeatherButtonStyle(prominent: modeRaw == mode.rawValue))
                }
            }
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

// MARK: - pages

#if os(macOS)
import AppKit
private typealias PlatformFont = NSFont
private typealias PlatformColor = NSColor
#else
import UIKit
private typealias PlatformFont = UIFont
private typealias PlatformColor = UIColor
#endif

/// Scroll the fic as one long page, or turn it like a book.
enum ReaderMode: String, CaseIterable, Identifiable {
    case pages, scroll
    var id: String { rawValue }
    var label: String { self == .pages ? "Pages" : "Scroll" }
}

/// The fic as one attributed string for TextKit to cut into pages, with
/// where each row starts so positions map both ways.
private struct PagedText {
    let text: NSAttributedString
    /// Character offset of each line's start, by line id.
    let lineStarts: [Int]
    let lines: [ReaderLines.Line]
    /// Section index → title, for the running head.
    let sectionTitles: [String]

    @MainActor
    static func build(_ book: EPUBBook, scale: CGFloat, palette: Palette) -> PagedText {
        let lines = ReaderLines.build(book)
        let ink = PlatformColor(palette.ink)
        let soft = PlatformColor(palette.inkSoft)
        let gold = PlatformColor(palette.gold)
        let rose = PlatformColor(palette.rose)

        func font(_ name: String, _ size: CGFloat) -> PlatformFont {
            PlatformFont(name: name, size: size * scale) ?? .systemFont(ofSize: size * scale)
        }
        let body = 18.0, quote = 17.0
        func para(spacing: CGFloat = 22, before: CGFloat = 0, indent: CGFloat = 0, line: CGFloat = 13,
                  align: NSTextAlignment = .natural) -> NSParagraphStyle {
            let p = NSMutableParagraphStyle()
            p.lineSpacing = line * scale
            p.paragraphSpacing = spacing * scale
            p.paragraphSpacingBefore = before * scale
            p.headIndent = indent
            p.firstLineHeadIndent = indent
            p.alignment = align
            return p
        }

        let out = NSMutableAttributedString()
        var starts: [Int] = []
        var titles: [String] = []
        for (i, section) in book.sections.enumerated() {
            let heading = section.blocks.first { if case .heading = $0.kind { return true } else { return false } }
            titles.append(section.title ?? heading?.text ?? book.title ?? "")
            _ = i
        }

        func appendRuns(_ runs: [EPUBBook.Run], size: CGFloat, italicBase: Bool, color: PlatformColor, style: NSParagraphStyle) {
            for run in runs {
                let italic = italicBase != run.italic
                let name = Typeface.readingName(italic: italic, heavy: run.bold)
                var attrs: [NSAttributedString.Key: Any] = [
                    .font: font(name, size), .foregroundColor: run.link != nil ? rose : color, .paragraphStyle: style,
                ]
                if run.underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                if let link = run.link { attrs[.link] = link }
                out.append(NSAttributedString(string: run.text, attributes: attrs))
            }
        }
        func newline(_ style: NSParagraphStyle) {
            out.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: style, .font: font(Typeface.readingName(italic: false, heavy: false), body)]))
        }

        var lastSection = -1
        for line in lines {
            if line.section != lastSection {
                // Each chapter opens a fresh page (form feed = container break).
                if lastSection >= 0 { out.append(NSAttributedString(string: "\u{000C}")) }
                lastSection = line.section
            }
            starts.append(out.length)
            switch line.content {
            case .block(let block):
                switch block.kind {
                case .rule:
                    let style = para(spacing: 22, before: 6, align: .center)
                    out.append(NSAttributedString(string: "❦", attributes: [
                        .font: PlatformFont(name: "ZapfDingbatsITC", size: 18 * scale) ?? font("Newsreader-Regular", 18),
                        .foregroundColor: gold, .paragraphStyle: style]))
                    newline(style)
                case .heading(let level):
                    if let chapter = BlockView.chapter(block.text) {
                        let style = para(spacing: 34, before: 40, line: 4)
                        out.append(NSAttributedString(string: String(format: "%02d   ", chapter.number), attributes: [
                            .font: font(Typeface.displayName(italic: false, heavy: false), 26), .foregroundColor: gold, .paragraphStyle: style]))
                        out.append(NSAttributedString(string: chapter.title ?? BlockView.spelledChapter(chapter.number), attributes: [
                            .font: font(Typeface.displayName(italic: true, heavy: false), 30), .foregroundColor: gold, .paragraphStyle: style]))
                        newline(style)
                    } else {
                        let style = para(spacing: level <= 2 ? 22 : 14, before: 8, line: 4)
                        let size: CGFloat = level <= 1 ? 32 : 26
                        out.append(NSAttributedString(string: block.text, attributes: [
                            .font: font(Typeface.displayName(italic: false, heavy: false), size), .foregroundColor: ink, .paragraphStyle: style]))
                        newline(style)
                    }
                case .paragraph:
                    let quoted = block.quoteDepth > 0
                    let style = para(spacing: quoted ? 16 : 22, indent: quoted ? 18 * CGFloat(block.quoteDepth) : 0, line: quoted ? 10 : 13)
                    appendRuns(block.runs, size: quoted ? quote : body, italicBase: quoted, color: quoted ? soft : ink, style: style)
                    newline(style)
                }
            case .note(let label, let blocks):
                // On a page the card becomes an indented, gold-labelled aside.
                let isSummary = label.lowercased().contains("summary")
                let labelStyle = para(spacing: 6, before: 10, indent: 18, line: 2)
                out.append(NSAttributedString(string: isSummary ? "The summary" : label, attributes: [
                    .font: font(Typeface.displayName(italic: true, heavy: false), 19), .foregroundColor: gold, .paragraphStyle: labelStyle]))
                newline(labelStyle)
                for (j, block) in blocks.enumerated() {
                    let style = para(spacing: j == blocks.count - 1 ? 28 : 12, indent: 18, line: 10)
                    if case .rule = block.kind { continue }
                    appendRuns(block.runs, size: quote, italicBase: !isSummary, color: isSummary ? ink : soft, style: style)
                    newline(style)
                }
            }
        }
        return PagedText(text: out, lineStarts: starts, lines: lines, sectionTitles: titles)
    }

    /// The line a character offset falls in.
    func line(at offset: Int) -> ReaderLines.Line? {
        var lo = 0, hi = lineStarts.count - 1, found: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lineStarts[mid] <= offset { found = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return found.map { lines[$0] }
    }
}

/// Character ranges of each page, cut by TextKit off the main thread.
private func paginate(_ text: NSAttributedString, size: CGSize) -> [NSRange] {
    let storage = NSTextStorage(attributedString: text)
    let manager = NSLayoutManager()
    storage.addLayoutManager(manager)
    var pages: [NSRange] = []
    while pages.count < 20_000 {
        let container = NSTextContainer(size: size)
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        let glyphs = manager.glyphRange(for: container)
        if glyphs.length == 0 { break }
        pages.append(manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil))
        if NSMaxRange(glyphs) >= manager.numberOfGlyphs { break }
    }
    return pages.isEmpty ? [NSRange(location: 0, length: text.length)] : pages
}

/// Draws one page of text with its own small TextKit stack.
private final class PageCanvas: PlatformView {
    var text = NSAttributedString() { didSet { rebuild() } }
    private let storage = NSTextStorage()
    private let manager = NSLayoutManager()
    private let container = NSTextContainer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        storage.addLayoutManager(manager)
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        #if os(iOS)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        #endif
    }
    required init?(coder: NSCoder) { fatalError() }

    #if os(macOS)
    override var isFlipped: Bool { true }
    override func layout() { super.layout(); rebuild() }
    #else
    override func layoutSubviews() { super.layoutSubviews(); rebuild() }
    #endif

    private func rebuild() {
        container.size = CGSize(width: bounds.width, height: .greatestFiniteMagnitude)
        storage.setAttributedString(text)
        #if os(macOS)
        needsDisplay = true
        #else
        setNeedsDisplay()
        #endif
    }

    override func draw(_ rect: CGRect) {
        let glyphs = manager.glyphRange(for: container)
        manager.drawBackground(forGlyphRange: glyphs, at: .zero)
        manager.drawGlyphs(forGlyphRange: glyphs, at: .zero)
    }
}

#if os(macOS)
private typealias PlatformView = NSView
private struct PageText: NSViewRepresentable {
    let text: NSAttributedString
    func makeNSView(context: Context) -> PageCanvas { PageCanvas(frame: .zero) }
    func updateNSView(_ view: PageCanvas, context: Context) { view.text = text }
}
#else
private typealias PlatformView = UIView
private struct PageText: UIViewRepresentable {
    let text: NSAttributedString
    func makeUIView(context: Context) -> PageCanvas { PageCanvas(frame: .zero) }
    func updateUIView(_ view: PageCanvas, context: Context) { view.text = text }
}
#endif

/// The fic as pages: TextKit fills each page to the bottom, chapters open on
/// a fresh page, and the place is kept by character, not by page number, so
/// a new text size or window size lands on the same sentence.
private struct PagedReader: View {
    let book: EPUBBook
    let scale: CGFloat
    let start: ReadingPosition?
    @Binding var jump: Int?
    let onPosition: (ReadingPosition) -> Void
    @Environment(\.palette) private var palette

    @State private var paged: PagedText?
    @State private var pages: [NSRange] = []
    @State private var page = 0
    /// The character the reader is at — survives re-pagination.
    @State private var anchor: Int?
    /// The page takes keyboard focus so arrows and space turn it.
    @FocusState private var focused: Bool

    private static let margin = CGSize(width: 32, height: 34)
    private static let furniture: CGFloat = 26  // running head and folio

    var body: some View {
        GeometryReader { geo in
            let pageSize = Self.textSize(in: geo.size, scale: scale)
            Group {
                if let paged, !pages.isEmpty {
                    pager(paged, pageSize: pageSize)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .task(id: "\(Int(pageSize.width))x\(Int(pageSize.height))@\(scale)-\(palette.ink.description)") {
                await layOut(pageSize)
            }
        }
        .onChange(of: jump) { _, section in
            guard let section, let paged else { return }
            if let line = paged.lines.first(where: { $0.section >= section }) {
                go(to: pageIndex(for: paged.lineStarts[line.id]))
            }
            jump = nil
        }
    }

    /// The text block on a page: the reading measure, the window's height.
    private static func textSize(in size: CGSize, scale: CGFloat) -> CGSize {
        let width = min(640 * min(scale, 1.15), size.width - margin.width * 2)
        let height = size.height - margin.height * 2 - furniture * 2
        return CGSize(width: max(200, width), height: max(200, height))
    }

    @ViewBuilder
    private func pager(_ paged: PagedText, pageSize: CGSize) -> some View {
        #if os(iOS)
        TabView(selection: Binding(get: { page }, set: { go(to: $0) })) {
            ForEach(pages.indices, id: \.self) { i in
                pageView(i, paged: paged, pageSize: pageSize).tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        #else
        pageView(page, paged: paged, pageSize: pageSize)
            .id(page)
            .transition(.opacity)
            .contentShape(Rectangle())
            // Click the left or right edge to turn back or on.
            .overlay {
                HStack(spacing: 0) {
                    Color.clear.contentShape(Rectangle()).onTapGesture { go(to: page - 1) }
                    Spacer().frame(width: pageSize.width * 0.6)
                    Color.clear.contentShape(Rectangle()).onTapGesture { go(to: page + 1) }
                }
            }
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onAppear { focused = true }
            .onKeyPress(.rightArrow) { go(to: page + 1); return .handled }
            .onKeyPress(.leftArrow) { go(to: page - 1); return .handled }
            .onKeyPress(.space) { go(to: page + 1); return .handled }
            .onKeyPress(.pageDown) { go(to: page + 1); return .handled }
            .onKeyPress(.pageUp) { go(to: page - 1); return .handled }
        #endif
    }

    private func pageView(_ i: Int, paged: PagedText, pageSize: CGSize) -> some View {
        let range = pages[i]
        let section = paged.line(at: range.location)?.section ?? 0
        return VStack(spacing: 0) {
            // Running head: the chapter, quiet.
            Text(paged.sectionTitles.indices.contains(section) ? paged.sectionTitles[section] : "")
                .textRole(.runningHead)
                .lineLimit(1)
                .frame(height: Self.furniture, alignment: .top)
            PageText(text: paged.text.attributedSubstring(from: range))
                .frame(width: pageSize.width, height: pageSize.height)
            Text("\(i + 1) of \(pages.count)")
                .textRole(.runningHead)
                .monospacedDigit()
                .frame(height: Self.furniture, alignment: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func layOut(_ size: CGSize) async {
        let built = PagedText.build(book, scale: scale, palette: palette)
        nonisolated(unsafe) let text = built.text
        let ranges = await Task.detached(priority: .userInitiated) { paginate(text, size: size) }.value
        guard !Task.isCancelled else { return }
        // Keep the place: the anchor character, or the saved position.
        let target: Int
        if let anchor {
            target = anchor
        } else if let start, let line = built.lines.first(where: { $0.section == start.section && $0.indexInSection >= start.block }) {
            target = built.lineStarts[line.id]
        } else {
            target = 0
        }
        paged = built
        pages = ranges
        page = pageIndex(for: target)
    }

    private func pageIndex(for offset: Int) -> Int {
        pages.lastIndex { $0.location <= offset } ?? 0
    }

    private func go(to index: Int) {
        guard let paged, pages.indices.contains(index) else { return }
        withAnimation(.easeInOut(duration: 0.18)) { page = index }
        anchor = pages[index].location
        if let line = paged.line(at: pages[index].location) {
            onPosition(ReadingPosition(section: line.section, block: line.indexInSection))
        }
    }
}

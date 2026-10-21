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
    @State private var waitingForCloud = false
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
            } else if waitingForCloud {
                LibraryLoadingView(text: "Downloading from iCloud…")
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .environment(\.readerImages, book?.images ?? [:])
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
        let url = item.url
        // Still in iCloud: ask for it and wait, rather than give up.
        if !FileManager.default.fileExists(atPath: url.path) {
            waitingForCloud = true
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            for _ in 0..<240 where !FileManager.default.fileExists(atPath: url.path) {
                try? await Task.sleep(for: .milliseconds(500))
                if Task.isCancelled { return }
            }
            waitingForCloud = false
            guard FileManager.default.fileExists(atPath: url.path) else {
                failure = "It hasn't finished downloading from iCloud. Check the connection and open it again."
                return
            }
        }
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
    var byline: Font { .display(21 * scale, relativeTo: .title3, italic: true) }
    var aside: Font { .reading(15 * scale, relativeTo: .callout, italic: true) }
    var table: Font { .reading(16 * scale, relativeTo: .callout) }
    var chat: Font { .reading(16 * scale, relativeTo: .callout) }
    var chatTitle: Font { .display(21 * scale, relativeTo: .title3) }
    var chatName: Font { .display(14 * scale, relativeTo: .caption, italic: true) }
    var chatNote: Font { .reading(13 * scale, relativeTo: .caption, italic: true) }
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
            /// "by evilphrog" under the title.
            case byline(EPUBBook.Block)
            /// Front matter around the summary ("Inspired by …"), set quietly.
            case aside(EPUBBook.Block)
        }
    }

    static func build(_ book: EPUBBook) -> [Line] {
        var out: [Line] = []
        for (s, section) in book.sections.enumerated() {
            let blocks = section.blocks
            // The title page: the section with the byline.
            let front = blocks.contains(where: BlockView.isByline)
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
                if BlockView.isByline(block) {
                    out.append(Line(id: out.count, content: .byline(block), section: s, indexInSection: b))
                } else if front, block.kind == .paragraph, block.quoteDepth == 0 {
                    out.append(Line(id: out.count, content: .aside(BlockView.unbulleted(block)), section: s, indexInSection: b))
                } else if !BlockView.isFurniture(block) {
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
                            case .byline(let block): BylineView(block: block, type: type)
                            case .aside(let block): AsideView(block: block, type: type)
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
                switch block.kind {
                case .rule:
                    Fleuron()
                case .paragraph, .heading:
                    // Links in the note's own ink: the clipping is paper.
                    Text(BlockView(block: block, type: type).styled(block.runs,
                        link: (isSummary || palette.silk ? palette : .paper).rose))
                        .font(isSummary ? type.body : type.quote)
                        .lineSpacing(type.lineSpacing * 0.8)
                        .multilineTextAlignment(block.alignment.text)
                        .frame(maxWidth: .infinity, alignment: block.alignment.frame)
                        .fixedSize(horizontal: false, vertical: true)
                case .image, .table, .chat:
                    BlockView(block: block, type: type)
                }
            }
        }
    }
}

/// "by evilphrog": quiet italic, the name in ink.
private struct BylineView: View {
    let block: EPUBBook.Block
    let type: ReadingType
    @Environment(\.palette) private var palette

    var body: some View {
        Text(BlockView(block: block, type: type).styled(block.runs, link: palette.ink))
            .font(type.byline)
            .foregroundStyle(palette.inkSoft)
            .padding(.top, -10 * type.scale)
            .padding(.bottom, 26 * type.scale)
    }
}

/// Title-page odds and ends ("Inspired by …"): small italic, out of the way.
private struct AsideView: View {
    let block: EPUBBook.Block
    let type: ReadingType
    @Environment(\.palette) private var palette

    var body: some View {
        Text(BlockView(block: block, type: type).styled(block.runs, link: palette.ink))
            .font(type.aside)
            .foregroundStyle(palette.inkSoft)
            .lineSpacing(type.lineSpacing * 0.6)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, type.paragraphSpacing * 0.6)
    }
}

extension EPUBBook.Block.Alignment {
    var text: TextAlignment {
        switch self {
        case .natural: .leading
        case .center: .center
        case .right: .trailing
        }
    }

    var frame: Alignment {
        switch self {
        case .natural: .leading
        case .center: .center
        case .right: .trailing
        }
    }
}

/// The book's images, by archive path, for the views that show them.
private struct ReaderImagesKey: EnvironmentKey {
    static let defaultValue: [String: Data] = [:]
}

extension EnvironmentValues {
    fileprivate var readerImages: [String: Data] {
        get { self[ReaderImagesKey.self] }
        set { self[ReaderImagesKey.self] = newValue }
    }
}

/// An image from the fic: from the EPUB itself, or (for ones AO3 left as
/// links) from the web. A missing image shows its alt text.
private struct ReaderImage: View {
    let source: String
    let alt: String
    let type: ReadingType
    @Environment(\.readerImages) private var images
    @Environment(\.palette) private var palette

    var body: some View {
        Group {
            if let data = images[source], let image = PlatformImage(data: data) {
                picture(Image(platformImage: image))
            } else if source.hasPrefix("http"), let url = URL(string: source) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        picture(image)
                    } else if phase.error != nil {
                        missing
                    } else {
                        ProgressView().frame(height: 80)
                    }
                }
            } else {
                missing
            }
        }
        .accessibilityLabel(alt.isEmpty ? "Image" : alt)
    }

    private func picture(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFit()
            .frame(maxHeight: 560 * type.scale)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
    }

    private var missing: some View {
        Label(alt.isEmpty ? "Image" : alt, systemImage: "photo")
            .font(type.aside)
            .foregroundStyle(palette.inkFaint)
    }
}

/// A table from the fic — a chat log, mostly — as a quiet grid.
private struct ReaderTable: View {
    let rows: [[[EPUBBook.Run]]]
    let type: ReadingType
    @Environment(\.palette) private var palette

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 16 * type.scale, verticalSpacing: 10 * type.scale) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { i, cell in
                        Text(BlockView(block: .init(kind: .paragraph, runs: cell, quoteDepth: 0), type: type).styled(cell))
                            .font(type.table)
                            .foregroundStyle(i == 0 && row.count > 1 ? palette.inkSoft : palette.ink)
                            .lineSpacing(type.lineSpacing * 0.5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.vertical, 12 * type.scale)
        .overlay(alignment: .top) { Hairline(gold: true) }
        .overlay(alignment: .bottom) { Hairline(gold: true) }
    }
}

/// A texting scene as a phone thread: the contact up top, timestamps
/// centered, the phone owner's messages on the right in rose, everyone
/// else's on the left.
private struct ChatThread: View {
    let chat: EPUBBook.Chat
    let type: ReadingType
    @Environment(\.palette) private var palette

    var body: some View {
        let me = chat.me
        VStack(spacing: 8 * type.scale) {
            if let title = chat.title {
                Text(title)
                    .font(type.chatTitle)
                    .foregroundStyle(palette.ink)
                    .multilineTextAlignment(.center)
                Hairline()
                    .padding(.bottom, 4 * type.scale)
            }
            ForEach(Array(chat.items.enumerated()), id: \.offset) { i, item in
                switch item {
                case .note(let text):
                    Text(text)
                        .font(type.chatNote)
                        .foregroundStyle(palette.inkFaint)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4 * type.scale)
                case .message(let sender, let runs):
                    let mine = sender == me
                    VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
                        if ChatLayout.showsName(chat, at: i, me: me) {
                            Text(sender)
                                .font(type.chatName)
                                .foregroundStyle(palette.inkFaint)
                                .padding(.horizontal, 4)
                        }
                        Text(BlockView(block: .init(kind: .paragraph, runs: runs, quoteDepth: 0), type: type).styled(runs))
                            .font(type.chat)
                            .foregroundStyle(palette.ink)
                            .lineSpacing(2 * type.scale)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 12 * type.scale)
                            .padding(.vertical, 7 * type.scale)
                            .background(ChatLayout.bubble(mine: mine, palette),
                                        in: RoundedRectangle(cornerRadius: 14 * type.scale, style: .continuous))
                    }
                    .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
                    .padding(mine ? .leading : .trailing, 56 * type.scale)
                case .image(let sender, let source, let alt):
                    ReaderImage(source: source, alt: alt, type: type)
                        .frame(maxWidth: 240 * type.scale, maxHeight: 320 * type.scale)
                        .frame(maxWidth: .infinity, alignment: sender == me ? .trailing : .leading)
                }
            }
        }
        .padding(18 * type.scale)
        .frame(maxWidth: 520 * type.scale)
        .debossed(cornerRadius: 22 * type.scale)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12 * type.scale)
    }
}

/// What both renderers of a chat agree on.
private enum ChatLayout {
    /// A name over someone else's message when the speaker changes — unless
    /// the thread is with just them, and its title already says so.
    static func showsName(_ chat: EPUBBook.Chat, at index: Int, me: String?) -> Bool {
        guard case .message(let sender, _) = chat.items[index], sender != me else { return false }
        let previous = chat.items[..<index].reversed().first { if case .message = $0 { return true } else { return false } }
        if case .message(let last, _) = previous, last == sender { return false }
        return !chat.isContact(sender) || chat.senders.count > 2
    }

    static func bubble(mine: Bool, _ palette: Palette) -> Color {
        mine ? palette.rose.opacity(0.42) : palette.raised2
    }
}

#if os(macOS)
private typealias PlatformImage = NSImage
extension Image {
    fileprivate init(platformImage: NSImage) { self.init(nsImage: platformImage) }
}
#else
private typealias PlatformImage = UIImage
extension Image {
    fileprivate init(platformImage: UIImage) { self.init(uiImage: platformImage) }
}
#endif

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
        case .image(let source, let alt):
            ReaderImage(source: source, alt: alt, type: type)
                .frame(maxWidth: .infinity, alignment: block.alignment == .right ? .trailing : .center)
                .padding(.vertical, 12 * type.scale)
                .padding(.bottom, type.paragraphSpacing * 0.5)
        case .table(let rows):
            ReaderTable(rows: rows, type: type)
                .padding(.bottom, type.paragraphSpacing)
        case .chat(let chat):
            ChatThread(chat: chat, type: type)
                .padding(.bottom, type.paragraphSpacing)
        case .paragraph:
            let quoted = block.quoteDepth > 0
            Text(styled(block.runs))
                .font(quoted ? type.quote : type.body)
                .foregroundStyle(quoted ? palette.inkSoft : palette.ink)
                .lineSpacing(quoted ? type.lineSpacing * 0.8 : type.lineSpacing)
                .multilineTextAlignment(block.alignment.text)
                .frame(maxWidth: .infinity, alignment: block.alignment.frame)
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

    /// AO3's "by author" line under the work's title.
    static func isByline(_ block: EPUBBook.Block) -> Bool {
        block.kind == .paragraph && block.quoteDepth == 0 && block.text.count < 300
            && block.text.trimmingCharacters(in: .whitespaces).hasPrefix("by ")
            && block.runs.contains { $0.link != nil }
    }

    /// A list item without the "• " the parser gives it.
    static func unbulleted(_ block: EPUBBook.Block) -> EPUBBook.Block {
        var block = block
        if let first = block.runs.first, first.text.hasPrefix("• ") {
            block.runs[0].text = String(first.text.dropFirst(2))
        }
        return block
    }

    /// A lone label line AO3 puts before a quoted summary or notes block.
    static func isLabel(_ block: EPUBBook.Block) -> Bool {
        block.quoteDepth == 0 && labels.contains(block.text.lowercased().trimmingCharacters(in: .punctuationCharacters))
    }

    /// Runs as one attributed string: italic and bold through presentation
    /// intents, so they pick the reading face's own italic and semibold.
    func styled(_ runs: [EPUBBook.Run], link linkColor: Color? = nil) -> AttributedString {
        var out = AttributedString()
        for run in runs {
            var piece = AttributedString(run.text)
            var intent: InlinePresentationIntent = []
            if run.italic { intent.insert(.emphasized) }
            if run.bold { intent.insert(.stronglyEmphasized) }
            if !intent.isEmpty { piece.inlinePresentationIntent = intent }
            if run.underline { piece.underlineStyle = .single }
            if run.strikethrough { piece.strikethroughStyle = .single }
            if run.baseline != .normal {
                let size = 18 * type.scale
                piece.font = .reading(size * 0.68, relativeTo: .caption, italic: run.italic, heavy: run.bold)
                piece.baselineOffset = run.baseline == .superscript ? size * 0.36 : -size * 0.12
            }
            if let link = run.link {
                piece.link = link
                piece.foregroundColor = linkColor ?? palette.rose
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
        // Sections with nothing to show (AO3's tag-only preface) are left out.
        let shown = Set(ReaderLines.build(book).map(\.section))
        return book.sections.enumerated().filter { shown.contains($0.offset) }.map { i, section in
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
    static func build(_ book: EPUBBook, scale: CGFloat, palette: Palette, pageSize: CGSize) -> PagedText {
        let lines = ReaderLines.build(book)
        let ink = PlatformColor(palette.ink)
        let soft = PlatformColor(palette.inkSoft)
        let gold = PlatformColor(palette.gold)
        let rose = PlatformColor(palette.rose)

        func font(_ name: String, _ size: CGFloat) -> PlatformFont {
            PlatformFont(name: name, size: size * scale) ?? .systemFont(ofSize: size * scale)
        }
        let body = 18.0, quote = 17.0
        func para(spacing: CGFloat = 22, before: CGFloat = 0, indent: CGFloat = 0, tail: CGFloat = 0, line: CGFloat = 13,
                  align: NSTextAlignment = .natural) -> NSParagraphStyle {
            let p = NSMutableParagraphStyle()
            p.lineSpacing = line * scale
            p.paragraphSpacing = spacing * scale
            p.paragraphSpacingBefore = before * scale
            p.headIndent = indent
            p.firstLineHeadIndent = indent
            p.tailIndent = -tail
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

        // No `.link` attribute: TextKit would draw it system blue and
        // underlined, and a drawn page can't follow it anyway.
        func appendRuns(_ runs: [EPUBBook.Run], size: CGFloat, italicBase: Bool, color: PlatformColor,
                        link: PlatformColor? = nil, display: Bool = false, style: NSParagraphStyle) {
            for run in runs {
                let italic = italicBase != run.italic
                let name = display ? Typeface.displayName(italic: italic, heavy: run.bold)
                                   : Typeface.readingName(italic: italic, heavy: run.bold)
                var attrs: [NSAttributedString.Key: Any] = [
                    .font: font(name, size), .foregroundColor: run.link != nil ? (link ?? rose) : color, .paragraphStyle: style,
                ]
                if run.underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                if run.strikethrough { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                if run.baseline != .normal {
                    attrs[.font] = font(name, size * 0.68)
                    attrs[.baselineOffset] = (run.baseline == .superscript ? size * 0.36 : -size * 0.12) * scale
                }
                // A <br> is a line break inside the paragraph (U+2028), not a
                // new paragraph with its spacing.
                out.append(NSAttributedString(string: run.text.replacingOccurrences(of: "\n", with: "\u{2028}"),
                                              attributes: attrs))
            }
        }
        func align(_ a: EPUBBook.Block.Alignment) -> NSTextAlignment {
            switch a {
            case .natural: .natural
            case .center: .center
            case .right: .right
            }
        }
        /// An image from the EPUB, scaled to fit the page; one that isn't in
        /// the book (AO3 left it as a link) shows its alt text.
        func appendImage(_ source: String, alt: String, alignment: EPUBBook.Block.Alignment,
                         widthFraction: CGFloat = 1, align textAlign: NSTextAlignment? = nil, indent: CGFloat = 0) {
            let style = para(spacing: 26, before: 8, indent: indent, tail: indent, line: 0,
                             align: textAlign ?? (alignment == .right ? .right : .center))
            if let data = book.images[source], let image = PlatformImage(data: data), image.size.width > 0 {
                let k = min(1, pageSize.width * widthFraction / image.size.width,
                            pageSize.height * 0.8 * widthFraction / image.size.height)
                let attachment = NSTextAttachment()
                attachment.image = image
                attachment.bounds = CGRect(x: 0, y: 0, width: image.size.width * k, height: image.size.height * k)
                let piece = NSMutableAttributedString(attachment: attachment)
                piece.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: piece.length))
                out.append(piece)
            } else {
                out.append(NSAttributedString(string: alt.isEmpty ? "Image" : alt, attributes: [
                    .font: font(Typeface.readingName(italic: true, heavy: false), 15),
                    .foregroundColor: PlatformColor(palette.inkFaint), .paragraphStyle: style]))
            }
            newline(style)
        }
        /// A table, row by row. Two-cell rows (a chat log: who, then what)
        /// hang the second cell at a shared column; wider rows run on.
        func appendTable(_ rows: [[[EPUBBook.Run]]], indent: CGFloat, color: PlatformColor) {
            let size: CGFloat = 16
            let cellFont = font(Typeface.readingName(italic: false, heavy: false), size)
            let widest = rows.filter { $0.count == 2 }
                .map { ($0[0].map(\.text).joined() as NSString).size(withAttributes: [.font: cellFont]).width }
                .max() ?? 0
            let column = indent + min(max(widest + 16 * scale, 60 * scale), pageSize.width * 0.35)
            for (r, row) in rows.enumerated() {
                let p = NSMutableParagraphStyle()
                p.lineSpacing = 6 * scale
                p.paragraphSpacing = (r == rows.count - 1 ? 24 : 8) * scale
                p.paragraphSpacingBefore = r == 0 ? 6 * scale : 0
                p.firstLineHeadIndent = indent
                p.headIndent = row.count == 2 ? column : indent
                p.tabStops = [NSTextTab(textAlignment: .natural, location: column)]
                for (c, cell) in row.enumerated() {
                    if c > 0 {
                        out.append(NSAttributedString(string: row.count == 2 ? "\t" : "   ·   ", attributes: [
                            .font: cellFont, .foregroundColor: PlatformColor(palette.inkFaint), .paragraphStyle: p]))
                    }
                    appendRuns(cell, size: size, italicBase: false,
                               color: c == 0 && row.count > 1 ? soft : color, style: p)
                }
                newline(p)
            }
        }
        /// Empty room inside a panel, above or below its text.
        func spacer(_ height: CGFloat) {
            let p = NSMutableParagraphStyle()
            p.minimumLineHeight = height * scale
            p.maximumLineHeight = height * scale
            out.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: p, .font: font(Typeface.readingName(italic: false, heavy: false), 4)]))
        }
        /// A texting scene on the phone panel, each message on its bubble
        /// (both drawn by PageCanvas behind the text).
        func appendChat(_ chat: EPUBBook.Chat) {
            let me = chat.me
            let pad: CGFloat = 26 * scale
            let far = pageSize.width * 0.28
            let start = out.length
            spacer(16)
            out.addAttribute(.readerPanelStart, value: true, range: NSRange(location: start, length: 1))
            if let title = chat.title {
                let style = para(spacing: 14, indent: pad, tail: pad, line: 2, align: .center)
                out.append(NSAttributedString(string: title, attributes: [
                    .font: font(Typeface.displayName(italic: false, heavy: false), 21), .foregroundColor: ink, .paragraphStyle: style]))
                newline(style)
            }
            for (i, item) in chat.items.enumerated() {
                switch item {
                case .note(let text):
                    let style = para(spacing: 10, before: 2, indent: pad, tail: pad, line: 2, align: .center)
                    out.append(NSAttributedString(string: text, attributes: [
                        .font: font(Typeface.readingName(italic: true, heavy: false), 13),
                        .foregroundColor: PlatformColor(palette.inkFaint), .paragraphStyle: style]))
                    newline(style)
                case .message(let sender, let runs):
                    let mine = sender == me
                    if ChatLayout.showsName(chat, at: i, me: me) {
                        let style = para(spacing: 4, indent: pad + 4, tail: far, line: 0)
                        out.append(NSAttributedString(string: sender, attributes: [
                            .font: font(Typeface.displayName(italic: true, heavy: false), 14),
                            .foregroundColor: PlatformColor(palette.inkFaint), .paragraphStyle: style]))
                        newline(style)
                    }
                    let inset = 12 * scale
                    let style = para(spacing: 16, indent: mine ? far : pad + inset, tail: mine ? pad + inset : far,
                                     line: 3, align: mine ? .right : .left)
                    let begin = out.length
                    appendRuns(runs, size: 16, italicBase: false, color: ink, style: style)
                    out.addAttribute(.readerBubble, value: mine ? BubbleKind.mine : BubbleKind.theirs,
                                     range: NSRange(location: begin, length: out.length - begin))
                    newline(style)
                case .image(let sender, let source, let alt):
                    appendImage(source, alt: alt, alignment: .natural, widthFraction: 0.5,
                                align: sender == me ? .right : .left, indent: pad)
                }
            }
            spacer(20)
            out.addAttribute(.readerPanelEnd, value: true, range: NSRange(location: out.length - 1, length: 1))
            out.addAttribute(.readerPanel, value: PanelKind.phone, range: NSRange(location: start, length: out.length - start))
            spacer(30)
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
                    let style = para(spacing: quoted ? 16 : 22, indent: quoted ? 18 * CGFloat(block.quoteDepth) : 0,
                                     line: quoted ? 10 : 13, align: align(block.alignment))
                    appendRuns(block.runs, size: quoted ? quote : body, italicBase: quoted, color: quoted ? soft : ink, style: style)
                    newline(style)
                case .image(let source, let alt):
                    appendImage(source, alt: alt, alignment: block.alignment)
                case .table(let rows):
                    appendTable(rows, indent: 18 * CGFloat(block.quoteDepth), color: ink)
                case .chat(let chat):
                    appendChat(chat)
                }
            case .note(let label, let blocks):
                // The summary in a stitched card, notes on a paper clipping:
                // the panel is drawn behind these characters (PageCanvas).
                let isSummary = label.lowercased().contains("summary")
                let colors = isSummary || palette.silk ? palette : Palette.paper
                let noteInk = PlatformColor(colors.ink)
                let pad: CGFloat = 26 * scale
                let start = out.length
                spacer(16)
                out.addAttribute(.readerPanelStart, value: true, range: NSRange(location: start, length: 1))
                let labelStyle = para(spacing: 6, indent: pad, tail: pad, line: 2)
                out.append(NSAttributedString(
                    string: isSummary ? "The summary" : label.prefix(1).uppercased() + label.dropFirst().lowercased(),
                    attributes: [.font: font(Typeface.displayName(italic: true, heavy: false), 19),
                                 .foregroundColor: PlatformColor(colors.gold), .paragraphStyle: labelStyle]))
                newline(labelStyle)
                let paragraphs = blocks.filter { if case .rule = $0.kind { return false } else { return true } }
                for (j, block) in paragraphs.enumerated() {
                    switch block.kind {
                    case .image(let source, let alt):
                        appendImage(source, alt: alt, alignment: block.alignment)
                    case .table(let rows):
                        appendTable(rows, indent: pad, color: noteInk)
                    case .chat:
                        break  // a thread inside an author's note: rare, and panels don't nest
                    default:
                        let style = para(spacing: j == paragraphs.count - 1 ? 0 : 12, indent: pad, tail: pad, line: 10,
                                         align: align(block.alignment))
                        appendRuns(block.runs, size: isSummary ? body : quote, italicBase: !isSummary, color: noteInk,
                                   link: PlatformColor(colors.rose), style: style)
                        newline(style)
                    }
                }
                spacer(20)
                out.addAttribute(.readerPanelEnd, value: true, range: NSRange(location: out.length - 1, length: 1))
                out.addAttribute(.readerPanel, value: isSummary ? PanelKind.card : PanelKind.clipping,
                                 range: NSRange(location: start, length: out.length - start))
                // Room below the panel, outside it.
                spacer(30)
            case .byline(let block):
                let style = para(spacing: 30, line: 4)
                appendRuns(block.runs, size: 21, italicBase: true, color: soft, link: ink, display: true, style: style)
                newline(style)
            case .aside(let block):
                let style = para(spacing: 12, line: 8)
                appendRuns(block.runs, size: 15, italicBase: true, color: soft, link: ink, style: style)
                newline(style)
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

/// Character ranges of each page, cut by TextKit off the main thread. A
/// panel split across pages keeps its padding on both: the page it breaks
/// from gives up `pad` at the bottom, the page it continues on at the top.
private func paginate(_ text: NSAttributedString, size: CGSize, pad: CGFloat) -> [NSRange] {
    let storage = NSTextStorage(attributedString: text)
    let manager = NSLayoutManager()
    storage.addLayoutManager(manager)
    var pages: [NSRange] = []
    var start = 0
    while pages.count < 20_000 {
        let top = PanelKind.continues(text, at: start) ? pad : 0
        let container = NSTextContainer(size: CGSize(width: size.width, height: size.height - top))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        var glyphs = manager.glyphRange(for: container)
        if glyphs.length == 0 { break }
        var chars = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        if PanelKind.breaks(text, before: NSMaxRange(chars)) {
            container.size = CGSize(width: size.width, height: size.height - top - pad)
            let shorter = manager.glyphRange(for: container)
            if shorter.length > 0 {
                glyphs = shorter
                chars = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            }
        }
        pages.append(chars)
        start = NSMaxRange(chars)
        if NSMaxRange(glyphs) >= manager.numberOfGlyphs { break }
    }
    return pages.isEmpty ? [NSRange(location: 0, length: text.length)] : pages
}

private enum PanelKind: String {
    case card, clipping, phone

    /// A page starting at `offset` opens partway through a panel.
    static func continues(_ text: NSAttributedString, at offset: Int) -> Bool {
        guard offset > 0, offset < text.length else { return false }
        let attrs = text.attributes(at: offset, effectiveRange: nil)
        return attrs[.readerPanel] != nil && attrs[.readerPanelStart] == nil && attrs[.readerPanelEnd] == nil
    }

    /// A page ending just before `end` cuts a panel in two.
    static func breaks(_ text: NSAttributedString, before end: Int) -> Bool {
        guard end > 0, end < text.length else { return false }
        let attrs = text.attributes(at: end - 1, effectiveRange: nil)
        return attrs[.readerPanel] != nil && attrs[.readerPanelEnd] == nil
    }
}

extension NSAttributedString.Key {
    /// Marks characters drawn on a panel (a `PanelKind`).
    fileprivate static let readerPanel = NSAttributedString.Key("parade.readerPanel")
    /// The panel's first and last characters (its padding spacers).
    fileprivate static let readerPanelStart = NSAttributedString.Key("parade.readerPanelStart")
    fileprivate static let readerPanelEnd = NSAttributedString.Key("parade.readerPanelEnd")
    /// A chat message's characters, drawn on a bubble (a `BubbleKind`).
    fileprivate static let readerBubble = NSAttributedString.Key("parade.readerBubble")
}

private enum BubbleKind {
    case mine, theirs
}

/// Draws one page of text with its own small TextKit stack, and the summary
/// card and note clippings behind their text.
private final class PageCanvas: PlatformView {
    var text = NSAttributedString() { didSet { rebuild() } }
    var palette = Palette.leather
    /// Padding a panel gets where a page cuts it.
    var pad: CGFloat = 18
    /// The page opens partway through a panel from the page before.
    var carried = false
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
        let all = manager.glyphRange(for: container)
        #if os(macOS)
        let context = NSGraphicsContext.current?.cgContext
        #else
        let context = UIGraphicsGetCurrentContext()
        #endif
        guard let cg = context else {
            manager.drawGlyphs(forGlyphRange: all, at: .zero)
            return
        }
        // A panel carried over from the last page: room above it, as
        // paginate() left for it.
        if carried { cg.translateBy(x: 0, y: pad) }
        var cursor = all.location
        storage.enumerateAttribute(.readerPanel, in: NSRange(location: 0, length: storage.length)) { value, chars, _ in
            guard let kind = value as? PanelKind else { return }
            // Only the bottom spacer spilled onto this page: no panel to draw.
            if chars.length == 1, storage.attribute(.readerPanelEnd, at: chars.location, effectiveRange: nil) != nil { return }
            let glyphs = manager.glyphRange(forCharacterRange: chars, actualCharacterRange: nil)
            manager.drawGlyphs(forGlyphRange: NSRange(location: cursor, length: max(0, glyphs.location - cursor)), at: .zero)
            var top = CGFloat.greatestFiniteMagnitude, bottom: CGFloat = 0
            manager.enumerateLineFragments(forGlyphRange: glyphs) { _, used, _, _, _ in
                top = min(top, used.minY)
                bottom = max(bottom, used.maxY)
            }
            guard top < bottom else { return }
            if carried, chars.location == 0 { top -= pad }
            if NSMaxRange(chars) == storage.length,
               storage.attribute(.readerPanelEnd, at: storage.length - 1, effectiveRange: nil) == nil {
                bottom += pad  // continues on the next page
            }
            let panel = CGRect(x: 0, y: top, width: bounds.width, height: bottom - top)
            cg.saveGState()
            if kind == .clipping, !palette.silk {
                // Tilted a touch, text and all, like the clipping elsewhere.
                cg.translateBy(x: panel.midX, y: panel.midY)
                cg.rotate(by: -0.5 * .pi / 180)
                cg.translateBy(x: -panel.midX, y: -panel.midY)
            }
            drawPanel(kind, in: panel, cg)
            if kind == .phone { drawBubbles(in: chars, cg) }
            manager.drawGlyphs(forGlyphRange: glyphs, at: .zero)
            cg.restoreGState()
            cursor = NSMaxRange(glyphs)
        }
        manager.drawGlyphs(forGlyphRange: NSRange(location: cursor, length: max(0, NSMaxRange(all) - cursor)), at: .zero)
    }

    /// Both pages draw y-down, but CoreGraphics shadow offsets ignore the
    /// Mac view's flip.
    #if os(macOS)
    private static let down: CGFloat = -1
    #else
    private static let down: CGFloat = 1
    #endif

    /// One rounded bubble behind each message paragraph.
    private func drawBubbles(in range: NSRange, _ cg: CGContext) {
        storage.enumerateAttribute(.readerBubble, in: range) { value, run, _ in
            guard let bubble = value as? BubbleKind else { return }
            let glyphs = manager.glyphRange(forCharacterRange: run, actualCharacterRange: nil)
            guard glyphs.length > 0 else { return }
            // Line by line: a wrapped paragraph's bounding box spans the
            // whole column, the bubble should hug the longest line.
            var rect = CGRect.null
            manager.enumerateLineFragments(forGlyphRange: glyphs) { _, _, _, lineGlyphs, _ in
                let part = NSIntersectionRange(lineGlyphs, glyphs)
                guard part.length > 0 else { return }
                rect = rect.union(self.manager.boundingRect(forGlyphRange: part, in: self.container))
            }
            guard !rect.isNull, rect.width > 0 else { return }
            rect = rect.insetBy(dx: -12, dy: -6)
            cg.saveGState()
            cg.addPath(CGPath(roundedRect: rect, cornerWidth: 13, cornerHeight: 13, transform: nil))
            cg.setFillColor(PlatformColor(ChatLayout.bubble(mine: bubble == .mine, palette)).cgColor)
            cg.fillPath()
            cg.restoreGState()
        }
    }

    private func drawPanel(_ kind: PanelKind, in rect: CGRect, _ cg: CGContext) {
        func cgColor(_ color: Color) -> CGColor { PlatformColor(color).cgColor }
        func fill(_ path: CGPath, _ top: Color, _ bottom: Color, shadow: (CGFloat, CGFloat, Double)) {
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: shadow.1 * Self.down), blur: shadow.0,
                         color: CGColor(gray: 0, alpha: shadow.2))
            cg.addPath(path)
            cg.setFillColor(cgColor(bottom))
            cg.fillPath()
            cg.restoreGState()
            cg.saveGState()
            cg.addPath(path)
            cg.clip()
            if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                         colors: [cgColor(top), cgColor(bottom)] as CFArray, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
            }
            cg.restoreGState()
        }
        func stroke(inset: CGFloat, radius: CGFloat, dashed: Bool) {
            cg.saveGState()
            let r = rect.insetBy(dx: inset + 0.5, dy: inset + 0.5)
            cg.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
            cg.setStrokeColor(cgColor(palette.goldFaint))
            cg.setLineWidth(1)
            if dashed { cg.setLineDash(phase: 0, lengths: [4, 3]) }
            cg.strokePath()
            cg.restoreGState()
        }

        switch kind {
        case .phone:
            // Pressed into the page, like the debossed fields elsewhere.
            fill(CGPath(roundedRect: rect, cornerWidth: 22, cornerHeight: 22, transform: nil),
                 palette.leatherDeep, palette.leatherDeep, shadow: (0, 0, 0))
            cg.saveGState()
            cg.addPath(CGPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 22, cornerHeight: 22, transform: nil))
            cg.setStrokeColor(cgColor(palette.rule))
            cg.setLineWidth(1)
            cg.strokePath()
            cg.restoreGState()
        case .card:
            fill(CGPath(roundedRect: rect, cornerWidth: 14, cornerHeight: 14, transform: nil),
                 palette.raised2, palette.raised, shadow: (15, 10, 0.28))
            stroke(inset: 7, radius: 9, dashed: !palette.solidStitch)
        case .clipping where palette.silk:
            fill(CGPath(roundedRect: rect, cornerWidth: 4, cornerHeight: 4, transform: nil),
                 palette.raised2, palette.raised, shadow: (15, 10, 0.28))
            stroke(inset: 6, radius: 2, dashed: false)
        case .clipping:
            fill(CGPath(roundedRect: rect, cornerWidth: 2, cornerHeight: 2, transform: nil),
                 Color(hex: 0xEFE4D3), Color(hex: 0xE3D4BF), shadow: (18, 14, 0.4))
        }
        if kind == .clipping {
            // Rose tape across the top-left corner.
            cg.saveGState()
            cg.translateBy(x: rect.minX + 52, y: rect.minY)
            cg.rotate(by: -3 * .pi / 180)
            cg.setFillColor(cgColor(palette.rose.opacity(0.4)))
            cg.fill(CGRect(x: -28, y: -9, width: 56, height: 18))
            cg.restoreGState()
        }
    }
}

#if os(macOS)
private typealias PlatformView = NSView
private struct PageText: NSViewRepresentable {
    let text: NSAttributedString
    var carried = false
    var pad: CGFloat = 18
    @Environment(\.palette) private var palette
    func makeNSView(context: Context) -> PageCanvas { PageCanvas(frame: .zero) }
    func updateNSView(_ view: PageCanvas, context: Context) {
        view.palette = palette
        view.carried = carried
        view.pad = pad
        view.text = text
    }
}
#else
private typealias PlatformView = UIView
private struct PageText: UIViewRepresentable {
    let text: NSAttributedString
    var carried = false
    var pad: CGFloat = 18
    @Environment(\.palette) private var palette
    func makeUIView(context: Context) -> PageCanvas { PageCanvas(frame: .zero) }
    func updateUIView(_ view: PageCanvas, context: Context) {
        view.palette = palette
        view.carried = carried
        view.pad = pad
        view.text = text
    }
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
    #if os(macOS)
    @State private var keyMonitor: Any?
    #endif

    private static let margin = CGSize(width: 32, height: 34)
    private static let furniture: CGFloat = 26  // running head and folio
    private static let panelPad: CGFloat = 18

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
            // Keys turn pages whatever has focus (the toolbar, a closed
            // popover): SwiftUI focus on a custom page view kept slipping.
            .onAppear {
                keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    turnPage(for: event) ? nil : event
                }
            }
            .onDisappear {
                if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
                keyMonitor = nil
            }
        #endif
    }

    private func pageView(_ i: Int, paged: PagedText, pageSize: CGSize) -> some View {
        let range = pages[i]
        let section = paged.line(at: range.location)?.section ?? 0
        // A chapter's opening page carries its own heading, as in a book.
        let opens = range.location == 0
            || (paged.text.string as NSString).character(at: range.location - 1) == 0x0C
        return VStack(spacing: 0) {
            // Running head: the chapter, quiet.
            Text(!opens && paged.sectionTitles.indices.contains(section) ? paged.sectionTitles[section] : "")
                .textRole(.runningHead)
                .lineLimit(1)
                .frame(height: Self.furniture, alignment: .top)
            PageText(text: paged.text.attributedSubstring(from: range),
                     carried: PanelKind.continues(paged.text, at: range.location),
                     pad: Self.panelPad * scale)
                .frame(width: pageSize.width, height: pageSize.height)
            Text("\(i + 1) of \(pages.count)")
                .textRole(.runningHead)
                .monospacedDigit()
                .frame(height: Self.furniture, alignment: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func layOut(_ size: CGSize) async {
        let built = PagedText.build(book, scale: scale, palette: palette, pageSize: size)
        nonisolated(unsafe) let text = built.text
        let pad = Self.panelPad * scale
        let ranges = await Task.detached(priority: .userInitiated) { paginate(text, size: size, pad: pad) }.value
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

    #if os(macOS)
    /// Arrows, space (Shift-space back), Page Up and Page Down.
    private func turnPage(for event: NSEvent) -> Bool {
        guard !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.option),
              !event.modifierFlags.contains(.control),
              !(event.window?.firstResponder is NSTextView)
        else { return false }
        switch event.keyCode {
        case 124, 121: go(to: page + 1)  // right, page down
        case 123, 116: go(to: page - 1)  // left, page up
        case 49: go(to: event.modifierFlags.contains(.shift) ? page - 1 : page + 1)  // space
        default: return false
        }
        return true
    }
    #endif

    private func go(to index: Int) {
        guard let paged, pages.indices.contains(index) else { return }
        withAnimation(.easeInOut(duration: 0.18)) { page = index }
        anchor = pages[index].location
        if let line = paged.line(at: pages[index].location) {
            onPosition(ReadingPosition(section: line.section, block: line.indexInSection))
        }
    }
}

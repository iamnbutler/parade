import SwiftUI
import AO3Kit

/// Rich metadata for one fic, parsed from inside its EPUB.
/// A sidebar pane on macOS; a pushed screen on iOS.
struct FicDetailView: View {
    let item: LibraryItem
    /// Where the fic sits in the list it was opened from ("Library, 3 of
    /// 26"); without one, the running head names its fandom.
    var runningHead: String?
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.readFic) private var readFic
    @State private var reading = false
    @State private var loaded: WorkDetails?
    /// The fic `loaded` belongs to (the Mac reuses this view across fics).
    @State private var loadedID: String?

    /// Cached details draw on the very first frame — no spinner flash, no
    /// height jump while a page slides in. While a fic is being updated the
    /// old details stay up until the new ones are read.
    private var details: WorkDetails? {
        model.cachedDetails(for: item) ?? (loadedID == item.id ? loaded : nil)
    }
    @State private var showNewCollection = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                // Actions first: a long summary would push them off screen.
                actions
                if let summary = details?.summary {
                    // The page's one bold object.
                    StitchedCard(label: "The summary") {
                        Text(summary)
                            .textRole(.body)
                            .textSelection(.enabled)
                    }
                }
                if let details {
                    statsRow(details)
                    Hairline()
                    metadata(details)
                    Fleuron()
                        .padding(.top, 8)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 40)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .leatherBackground()
        .task(id: item.id + String(item.date.timeIntervalSince1970)) {
            guard model.cachedDetails(for: item) == nil else { return }
            let parsed = await model.details(for: item)
            loaded = parsed
            loadedID = item.id
        }
        .newCollectionAlert(isPresented: $showNewCollection, adding: item, model: model)
        #if os(iOS)
        .fullScreenCover(isPresented: $reading) {
            NavigationStack {
                ReaderView(item: item)
                    .navigationTitle(item.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { reading = false }
                        }
                    }
            }
            .themedWindow()
            .palette(palette)
        }
        #endif
    }

    private func read() {
        if let readFic {
            readFic(item)
        } else {
            reading = true
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let head = runningHead ?? details?.fandoms.first {
                Text(head).textRole(.runningHead).lineLimit(1)
            }
            Text(details?.title ?? item.title)
                .textRole(.title)
                .fixedSize(horizontal: false, vertical: true)
            Text("by \(details?.authors.joined(separator: " & ") ?? item.author)")
                .textRole(.dek)
            if let series = details?.series {
                if let name = details?.seriesName {
                    TagLink(tag: TagSelection(kind: .series, name: name)) {
                        Text(series)
                            .textRole(.meta)
                            .foregroundStyle(palette.rose)
                    }
                } else {
                    Text(series).textRole(.meta)
                }
            }
            let collections = model.collections.collections(containing: item.id)
            if !collections.isEmpty {
                Text("Kept in \(collections.joined(separator: ", "))")
                    .textRole(.meta)
            }
        }
    }

    private var actions: some View {
        // Wraps rather than squeezing labels on a narrow phone.
        FlowLayout(spacing: 8) {
            Button(action: read) {
                Label("Read", systemImage: "book")
            }
            .buttonStyle(.leatherProminent)
            .disabled(!item.isDownloaded)
            .help("Read this fic in Parade")
            // Always available; prominent when a check found an update.
            updateButton
                .buttonStyle(LeatherButtonStyle(prominent: model.hasUpdate(item)))
            if item.isDownloaded {
                #if os(iOS)
                ShareLink(item: item.url) {
                    Label("Books", systemImage: "book.closed")
                }
                .buttonStyle(.leather)
                #else
                Button {
                    model.addToBooks(item)
                } label: {
                    Label("Books", systemImage: "book.closed")
                }
                .buttonStyle(.leather)
                #endif
            }
            if let url = details?.workURL {
                Link(destination: url) {
                    Label("AO3", systemImage: "safari")
                }
                .buttonStyle(.leather)
            }
            Button {
                model.toggleFavorite(item)
            } label: {
                Label(model.isFavorite(item) ? "Favorited" : "Favorite",
                      systemImage: model.isFavorite(item) ? "star.fill" : "star")
            }
            .buttonStyle(.leather)
            Menu {
                CollectionMenuItems(item: item, showNewCollection: $showNewCollection)
            } label: {
                Label("Collections", systemImage: "rectangle.stack")
            }
            .menuStyle(.button)
            .buttonStyle(.leather)
            .fixedSize()
        }
    }

    private var updateButton: some View {
        Button {
            Task { await model.update(item) }
        } label: {
            Label("Update", systemImage: model.hasUpdate(item) ? "arrow.down.circle.fill" : "arrow.down.circle")
        }
        .disabled(model.isWorking)
        .help("Download this fic again from AO3")
    }

    private func metadata(_ d: WorkDetails) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            facts(d)
            field("Fandom", d.fandoms, kind: .fandoms)
            field("Relationships", d.relationships, kind: .relationships)
            field("Characters", d.characters, kind: .characters)
            field("Tags", d.additionalTags, kind: .tags)
        }
    }

    @ViewBuilder
    private func statsRow(_ d: WorkDetails) -> some View {
        let parts: [String] = [
            d.words.map { "\($0) words" },
            d.chapters.map { "\($0) chapters" },
            d.updated.map { "updated \(Self.readableDate($0))" }
                ?? d.published.map { "published \(Self.readableDate($0))" },
        ].compactMap { $0 }
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .textRole(.meta)
        }
    }

    /// Rating, warnings and category as a small two-column table: italic
    /// gold labels, plain values.
    private func facts(_ d: WorkDetails) -> some View {
        let rows = [("Rating", d.rating), ("Warnings", d.warnings), ("Category", d.categories)]
            .filter { !$0.1.isEmpty }
        return Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
            ForEach(rows, id: \.0) { label, values in
                GridRow {
                    Text(label).textRole(.kicker)
                    Text(values.joined(separator: ", "))
                        .textRole(.body)
                        .textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder
    private func field(_ label: String, _ values: [String], kind: TagKind? = nil) -> some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(label).textRole(.kicker)
                if let kind {
                    // Tap a tag to see every fic that has it.
                    TagChips(kind: kind, values: values)
                } else {
                    Text(values.joined(separator: " · "))
                        .textRole(.body)
                        .textSelection(.enabled)
                }
            }
        }
    }

    /// AO3's "2026-01-15" as "Jan 15, 2026"; anything unexpected as-is.
    private static func readableDate(_ iso: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: iso) else { return iso }
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        style.timeZone = TimeZone(identifier: "UTC")!
        return date.formatted(style)
    }
}

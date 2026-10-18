import SwiftUI
import AO3Kit

/// Rich metadata for one fic, parsed from inside its EPUB.
/// A sidebar pane on macOS; a pushed screen on iOS.
struct FicDetailView: View {
    let item: LibraryItem
    @EnvironmentObject private var model: AppModel
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
            VStack(alignment: .leading, spacing: 14) {
                header
                actions
                if let details {
                    if let summary = details.summary {
                        Text(summary)
                            .font(.callout)
                            .foregroundStyle(.primary)
                    }
                    Divider()
                    metadata(details)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                }
                Spacer(minLength: 0)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: item.id + String(item.date.timeIntervalSince1970)) {
            guard model.cachedDetails(for: item) == nil else { return }
            let parsed = await model.details(for: item)
            loaded = parsed
            loadedID = item.id
        }
        .newCollectionAlert(isPresented: $showNewCollection, adding: item, model: model)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(details?.title ?? item.title)
                .font(.title3.weight(.semibold))
            Text(details?.authors.joined(separator: " & ") ?? item.author)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let series = details?.series {
                if let name = details?.seriesName {
                    TagLink(tag: TagSelection(kind: .series, name: name)) {
                        Text(series)
                            .font(.subheadline)
                            .foregroundStyle(.tint)
                    }
                } else {
                    Text(series)
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                }
            }
            let collections = model.collections.collections(containing: item.id)
            if !collections.isEmpty {
                Label(collections.joined(separator: ", "), systemImage: "rectangle.stack")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    private var actions: some View {
        // Wraps rather than squeezing labels on a narrow phone.
        FlowLayout(spacing: 8) {
            // Always available; prominent when a check found an update.
            if model.hasUpdate(item) {
                updateButton.buttonStyle(.borderedProminent)
            } else {
                updateButton.buttonStyle(.bordered)
            }
            if item.isDownloaded {
                #if os(iOS)
                ShareLink(item: item.url) {
                    Label("Books", systemImage: "book.closed.fill")
                }
                .buttonStyle(.bordered)
                #else
                Button {
                    model.addToBooks(item)
                } label: {
                    Label("Books", systemImage: "book.closed.fill")
                }
                #endif
            }
            if let url = details?.workURL {
                Link(destination: url) {
                    Label("AO3", systemImage: "safari")
                }
                .buttonStyle(.bordered)
            }
            Button {
                model.toggleFavorite(item)
            } label: {
                Label(model.isFavorite(item) ? "Favorited" : "Favorite",
                      systemImage: model.isFavorite(item) ? "star.fill" : "star")
            }
            .buttonStyle(.bordered)
            Menu {
                CollectionMenuItems(item: item, showNewCollection: $showNewCollection)
            } label: {
                Label("Collections", systemImage: "rectangle.stack")
            }
            #if os(iOS)
            .buttonStyle(.bordered)
            #else
            .fixedSize()
            #endif
        }
        .controlSize(.small)
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
        VStack(alignment: .leading, spacing: 10) {
            statsRow(d)
            field("Rating", d.rating)
            field("Warnings", d.warnings)
            field("Category", d.categories)
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
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func field(_ label: String, _ values: [String], kind: TagKind? = nil) -> some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(label.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                if let kind {
                    // Tap a tag to see every fic that has it.
                    TagChips(kind: kind, values: values)
                } else {
                    Text(values.joined(separator: " · "))
                        .font(.callout)
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

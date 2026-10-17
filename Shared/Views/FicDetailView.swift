import SwiftUI
import AO3Kit

/// Rich metadata for one fic, parsed from inside its EPUB.
/// A sidebar pane on macOS; a pushed screen on iOS.
struct FicDetailView: View {
    let item: LibraryItem
    @EnvironmentObject private var model: AppModel
    @State private var details: WorkDetails?
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
            details = nil
            details = await model.details(for: item)
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
                    NavigationLink(value: TagSelection(kind: .series, name: name)) {
                        Text(series)
                            .font(.subheadline)
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
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
            if model.hasUpdate(item) {
                Button {
                    Task { await model.update(item) }
                } label: {
                    Label("Update", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isWorking)
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
                #if os(macOS)
                .buttonStyle(.bordered)
                #endif
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
                if !model.hasUpdate(item) {
                    Divider()
                    Button {
                        Task { await model.update(item) }
                    } label: {
                        Label("Update from AO3", systemImage: "arrow.down.circle")
                    }
                    .disabled(model.isWorking)
                }
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
            d.updated.map { "updated \($0)" } ?? d.published.map { "published \($0)" },
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
}

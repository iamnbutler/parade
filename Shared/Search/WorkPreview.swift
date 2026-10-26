import SwiftUI
import AO3Kit

/// A search result in full, before it's saved: everything the listing
/// showed, and the ways to keep it. Built from the result itself; opening
/// it asks AO3 for nothing.
struct WorkPreview: View {
    let work: WorkBlurb
    @EnvironmentObject private var search: SearchModel
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                actions
                if let summary = work.summary {
                    StitchedCard(label: "The summary") {
                        Text(summary)
                            .textRole(.body)
                            .textSelection(.enabled)
                    }
                }
                Text(WorkFacts.line(work)).textRole(.meta)
                Hairline()
                VStack(alignment: .leading, spacing: 18) {
                    field("Fandom", work.fandoms)
                    field("Warnings", work.warnings.filter { $0 != "No Archive Warnings Apply" }, tappable: false)
                    field("Relationships", work.relationships)
                    field("Characters", work.characters)
                    field("Tags", work.freeforms)
                }
                Fleuron().padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 40)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .leatherBackground()
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let head = work.fandoms.first {
                Text(head).textRole(.runningHead).lineLimit(1)
            }
            Text(work.title)
                .textRole(.title)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Text("by \(work.authors.joined(separator: " & "))").textRole(.dek)
            ForEach(work.series, id: \.self) { series in
                Text(series).textRole(.meta)
            }
            OwnedMark(work: work)
        }
    }

    private var actions: some View {
        FlowLayout(spacing: 8) {
            if search.owned[work.id] == nil {
                Button { search.save(work, toRead: true, model: model) } label: {
                    Label("Save to To Read", systemImage: "bookmark")
                }
                .buttonStyle(.leatherProminent)
                .disabled(search.saving.contains(work.id))
                Button { search.save(work, toRead: false, model: model) } label: {
                    Label("Save to Library", systemImage: "books.vertical")
                }
                .buttonStyle(.leather)
                .disabled(search.saving.contains(work.id))
            }
            Link(destination: work.url) {
                Label("AO3", systemImage: "safari")
            }
            .buttonStyle(.leather)
            Menu {
                BlurbActions(work: work)
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .menuStyle(.button)
            .buttonStyle(.leather)
            .fixedSize()
        }
    }

    /// A labelled run of tags. Each one can join the search or be hidden.
    @ViewBuilder
    private func field(_ label: String, _ values: [String], tappable: Bool = true) -> some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(label).textRole(.kicker)
                FlowLayout(spacing: 6) {
                    ForEach(values, id: \.self) { value in
                        if tappable {
                            Menu {
                                Button { search.include(tag: value) } label: {
                                    Label("Add to Search", systemImage: "plus.magnifyingglass")
                                }
                                Button { search.hide(tag: value) } label: {
                                    Label("Hide Fics with This", systemImage: "eye.slash")
                                }
                            } label: {
                                Chip(text: value, selected: isIncluded(value))
                                    .multilineTextAlignment(.leading)
                            }
                            .menuStyle(.button)
                            .buttonStyle(.plain)
                            // Not fixedSize: a long fandom name wraps instead of
                            // widening the page past its column.
                            .menuIndicator(.hidden)
                        } else {
                            Chip(text: value)
                        }
                    }
                }
            }
        }
    }

    private func isIncluded(_ name: String) -> Bool {
        let tag = TagRef(name: name)
        return (search.profile.fandoms + search.profile.includeTags).contains { $0.isSame(as: tag) }
    }
}

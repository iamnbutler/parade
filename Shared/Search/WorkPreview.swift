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
                    field("Fandom", work.fandoms, kind: .fandom)
                    fixedField("Warnings", work.warnings, FixedTag.warnings, \.warnings)
                    fixedField("Category", work.categories, FixedTag.categories, \.categories)
                    field("Relationships", work.relationships, kind: .relationship)
                    field("Characters", work.characters, kind: .character)
                    field("Tags", work.freeforms, kind: .freeform)
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

    /// A labelled run of tags. Each one can be included in the search or
    /// excluded from it.
    @ViewBuilder
    private func field(_ label: String, _ values: [String], kind: TagField) -> some View {
        if !values.isEmpty {
            chips(label, values) { value in
                search.inclusion(of: value, kind: kind)
            } set: { value, inclusion in
                search.set(value, kind: kind, to: inclusion)
            }
        }
    }

    /// Warnings or categories: AO3's fixed tags, set by id.
    @ViewBuilder
    private func fixedField(_ label: String, _ values: [String], _ known: [FixedTag],
                            _ path: WritableKeyPath<SearchProfile, [Int: Inclusion]>) -> some View {
        if !values.isEmpty {
            chips(label, values) { value in
                known.first { $0.name == value }.flatMap { search.profile[keyPath: path][$0.id] }
            } set: { value, inclusion in
                guard let tag = known.first(where: { $0.name == value }) else { return }
                search.profile[keyPath: path][tag.id] = inclusion
            }
        }
    }

    private func chips(_ label: String, _ values: [String],
                       state: @escaping (String) -> Inclusion?,
                       set: @escaping (String, Inclusion) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).textRole(.kicker)
            FlowLayout(spacing: 6) {
                ForEach(values, id: \.self) { value in
                    Menu {
                        Button { set(value, .include) } label: {
                            Label("Include in Search", systemImage: "checkmark.circle")
                        }
                        Button { set(value, .exclude) } label: {
                            Label("Exclude from Search", systemImage: "nosign")
                        }
                    } label: {
                        Chip(text: value, selected: state(value) == .include)
                            .strikethrough(state(value) == .exclude)
                            .multilineTextAlignment(.leading)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    // Not fixedSize: a long fandom name wraps instead of
                    // widening the page past its column.
                    .menuIndicator(.hidden)
                }
            }
        }
    }
}

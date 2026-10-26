import SwiftUI
import AO3Kit

/// The search's settings as a row of chips: tap one to change it. Toggles
/// flip in place; lists open an editor.
struct SearchFilterBar: View {
    @EnvironmentObject private var search: SearchModel
    @State private var editing: Editor?

    enum Editor: String, Identifiable {
        case fandoms, tags, hidden
        var id: String { rawValue }
    }

    private var profile: SearchProfile { search.profile }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(fandomLabel, selected: !profile.fandoms.isEmpty) { editing = .fandoms }
                chip("Explicit only", selected: profile.explicitOnly) { search.profile.explicitOnly.toggle() }
                chip("Complete only", selected: profile.completeOnly) { search.profile.completeOnly.toggle() }
                chip(profile.includeTags.isEmpty ? "+ Tags" : "Tags · \(profile.includeTags.count)",
                     selected: !profile.includeTags.isEmpty) { editing = .tags }
                chip("Not mine", selected: profile.hideOwned) { search.profile.hideOwned.toggle() }
                let hiddenCount = profile.hiddenTags.count + profile.hiddenAuthors.count
                chip(hiddenCount == 0 ? "Hidden" : "Hidden · \(hiddenCount)", selected: hiddenCount > 0) { editing = .hidden }
                sortMenu
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .sheet(item: $editing) { editor in
            NavigationStack {
                Group {
                    switch editor {
                    case .fandoms: FandomEditor()
                    case .tags: TagEditor(kind: .include)
                    case .hidden: TagEditor(kind: .hidden)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { editing = nil }
                    }
                }
            }
            .themedWindow()
            #if os(macOS)
            .frame(minWidth: 420, minHeight: 480)
            #endif
        }
    }

    private var fandomLabel: String {
        switch profile.fandoms.count {
        case 0: "All of AO3"
        case 1: profile.fandoms[0].displayName
        default: "\(profile.fandoms.count) fandoms"
        }
    }

    private func chip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Chip(text: text, selected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $search.profile.sort) {
                ForEach(AO3WorkQuery.Sort.allCases.filter { $0 != .words }) { sort in
                    Text(sort.label).tag(sort)
                }
            }
        } label: {
            Chip(text: "Sort: \(search.profile.effectiveSort.label)", selected: false)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
    }
}

/// The fandoms a search covers: remove any, add from the library or by
/// name, or start over from the library's.
struct FandomEditor: View {
    @EnvironmentObject private var search: SearchModel
    @EnvironmentObject private var model: AppModel
    @State private var adding = ""
    @State private var confirmClear = false

    var body: some View {
        List {
            Section {
                AddTagField(text: $adding, prompt: "Add a fandom", suggestions: suggestions) { name in
                    add(TagRef(name: name))
                }
            }
            .leatherRows()
            Section {
                if search.profile.fandoms.isEmpty {
                    Text("No fandoms: the search covers all of AO3.").textRole(.subtitle)
                }
                ForEach(search.profile.fandoms, id: \.self) { tag in
                    TagRefRow(tag: tag, count: search.libraryCount(of: tag))
                }
                .onDelete { search.profile.fandoms.remove(atOffsets: $0) }
                .onMove { search.profile.fandoms.move(fromOffsets: $0, toOffset: $1) }
            } header: {
                SectionHeading(name: "Searching", count: search.profile.fandoms.count)
            } footer: {
                Text("Fics in any of these. Swipe to remove one.").textRole(.meta)
            }
            .leatherRows()
            let missing = search.unsearchedLibraryFandoms
            if !missing.isEmpty {
                Section {
                    ForEach(missing, id: \.name) { fandom in
                        Button { add(TagRef(name: fandom.name)) } label: {
                            HStack {
                                Image(systemName: "plus.circle")
                                Text(fandom.name).textRole(.body).lineLimit(1)
                                Spacer()
                                Numeral(value: fandom.count)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    SectionHeading(name: "In your library, not in your search")
                }
                .leatherRows()
            }
            Section {
                Button("Reset to My Library's Fandoms") { search.resetToLibrary() }
                Button("Clear Fandoms, Words and Tags") { confirmClear = true }
            }
            .leatherRows()
        }
        .leatherList()
        .navigationTitle("Fandoms")
        .confirmationDialog("Clear the search?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { search.profile.clear() }
        } message: {
            Text("Hidden tags and authors stay hidden.")
        }
    }

    private var suggestions: [String] {
        let fandoms = Set(model.detailsIndex.values.flatMap(\.fandoms))
        return model.searchVocabulary.filter { $0.kind == .tag && fandoms.contains($0.text) }.map(\.text)
    }

    private func add(_ tag: TagRef) {
        guard !search.profile.fandoms.contains(where: { $0.isSame(as: tag) }) else { return }
        search.profile.fandoms.append(tag)
    }
}

/// Tags a fic must have, or tags and authors never to show.
struct TagEditor: View {
    enum Kind { case include, hidden }
    let kind: Kind
    @EnvironmentObject private var search: SearchModel
    @EnvironmentObject private var model: AppModel
    @State private var adding = ""
    @State private var addingAuthor = ""

    private var tags: Binding<[TagRef]> {
        kind == .include ? $search.profile.includeTags : $search.profile.hiddenTags
    }

    var body: some View {
        List {
            Section {
                AddTagField(text: $adding, prompt: kind == .include ? "Add a ship, character or tag" : "Hide a tag",
                            suggestions: suggestions) { name in
                    let tag = TagRef(name: name)
                    guard !tags.wrappedValue.contains(where: { $0.isSame(as: tag) }) else { return }
                    tags.wrappedValue.append(tag)
                }
            }
            .leatherRows()
            Section {
                if tags.wrappedValue.isEmpty {
                    Text(kind == .include ? "No tags: any fic in your fandoms." : "Nothing hidden.")
                        .textRole(.subtitle)
                }
                ForEach(tags.wrappedValue, id: \.self) { tag in
                    TagRefRow(tag: tag)
                }
                .onDelete { tags.wrappedValue.remove(atOffsets: $0) }
            } header: {
                SectionHeading(name: kind == .include ? "Every fic has all of these" : "Hidden tags",
                               count: tags.wrappedValue.count)
            } footer: {
                Text(kind == .include
                     ? "Swipe to remove one."
                     : "Fics with any of these never show. Swipe to unhide.")
                    .textRole(.meta)
            }
            .leatherRows()
            if kind == .hidden {
                Section {
                    AddTagField(text: $addingAuthor, prompt: "Hide an author", suggestions: []) { name in
                        if !search.profile.hiddenAuthors.contains(name) { search.profile.hiddenAuthors.append(name) }
                    }
                    ForEach(search.profile.hiddenAuthors, id: \.self) { author in
                        Text(author).textRole(.body)
                    }
                    .onDelete { search.profile.hiddenAuthors.remove(atOffsets: $0) }
                } header: {
                    SectionHeading(name: "Hidden authors", count: search.profile.hiddenAuthors.count)
                }
                .leatherRows()
            }
        }
        .leatherList()
        .navigationTitle(kind == .include ? "Tags" : "Hidden")
    }

    /// The library's ships, characters and tags, most used first.
    private var suggestions: [String] {
        let fandoms = Set(model.detailsIndex.values.flatMap(\.fandoms))
        return model.searchVocabulary.filter { $0.kind == .tag && !fandoms.contains($0.text) }.map(\.text)
    }
}

/// One tag in an editor: as picked, and what AO3 calls it if different.
private struct TagRefRow: View {
    let tag: TagRef
    var count: Int?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tag.displayName).textRole(.body).lineLimit(2)
                if let canonical = tag.canonical, canonical.caseInsensitiveCompare(tag.name) != .orderedSame {
                    Text("from \(tag.name)").textRole(.meta).lineLimit(1)
                }
            }
            Spacer()
            if let count, count > 0 { Numeral(value: count) }
        }
    }
}

/// A field that adds what's typed, suggesting matches from the library as
/// you go. Anything typed can be added: it's looked up on AO3 at search.
private struct AddTagField: View {
    @Binding var text: String
    let prompt: String
    let suggestions: [String]
    let add: (String) -> Void

    private var matches: [String] {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return Array(suggestions.lazy.filter { $0.localizedCaseInsensitiveContains(query) }.prefix(6))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField(prompt, text: $text)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .onSubmit { commit(text) }
                if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("Add") { commit(text) }
                        .buttonStyle(.leather)
                }
            }
            ForEach(matches, id: \.self) { match in
                Button { commit(match) } label: {
                    Label(match, systemImage: "plus")
                        .textRole(.small)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func commit(_ value: String) {
        let name = value.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        add(name)
        text = ""
    }
}

import SwiftUI
import AO3Kit

/// The kinds of tag a search can want or refuse, each its own section.
enum TagField: String, CaseIterable, Identifiable {
    case fandom, relationship, character, freeform

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fandom: "Fandoms"
        case .relationship: "Relationships"
        case .character: "Characters"
        case .freeform: "Additional tags"
        }
    }

    var singular: String {
        switch self {
        case .fandom: "fandom"
        case .relationship: "relationship"
        case .character: "character"
        case .freeform: "tag"
        }
    }

    /// The library's tags of this kind, most used first.
    @MainActor
    func suggestions(_ model: AppModel) -> [String] {
        var counts: [String: Int] = [:]
        for d in model.detailsIndex.values {
            let values: [String] = switch self {
            case .fandom: d.fandoms
            case .relationship: d.relationships
            case .character: d.characters
            case .freeform: d.additionalTags
            }
            for value in Set(values) { counts[value, default: 0] += 1 }
        }
        return counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
    }
}

extension SearchProfile {
    /// One kind's tags as include and exclude lists. Fandoms include as
    /// "any of"; the others as "all of".
    func rule(_ kind: TagField) -> TagRule {
        switch kind {
        case .fandom: TagRule(include: fandoms, exclude: excludedFandoms)
        case .relationship: relationships
        case .character: characters
        case .freeform: freeforms
        }
    }

    mutating func setRule(_ rule: TagRule, _ kind: TagField) {
        switch kind {
        case .fandom:
            fandoms = rule.include
            excludedFandoms = rule.exclude
        case .relationship: relationships = rule
        case .character: characters = rule
        case .freeform: freeforms = rule
        }
    }
}

/// Setting up a search: every option on one page, in the book's form
/// style. Edits a copy; nothing is asked of AO3 until Search.
struct SearchForm: View {
    @EnvironmentObject private var search: SearchModel
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = SearchProfile()
    @State private var confirmClear = false
    /// A section to open scrolled to ("categories", "tags", "end"), for
    /// screenshots of the rest of the form.
    var scrolledTo: String?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            Form {
                wordsSection
                TagRuleSection(kind: .fandom, rule: ruleBinding(.fandom))
                crossoverSection
                ratingSection
                FixedTagSection(title: "Archive warnings", tags: FixedTag.warnings, choices: $draft.warnings,
                                footer: "Include: fics with any of these. Exclude: fics with none of them.")
                FixedTagSection(title: "Categories", tags: FixedTag.categories, choices: $draft.categories,
                                footer: "Include: fics in any of these. Exclude: fics in none of them.")
                    .id("categories")
                TagRuleSection(kind: .relationship, rule: ruleBinding(.relationship))
                    .id("tags")
                TagRuleSection(kind: .character, rule: ruleBinding(.character))
                TagRuleSection(kind: .freeform, rule: ruleBinding(.freeform))
                workSection
                orderSection
                librarySection
                resetSection
                    .id("end")
            }
            .leatherForm()
            .task {
                guard let scrolledTo else { return }
                try? await Task.sleep(for: .milliseconds(300))
                proxy.scrollTo(scrolledTo, anchor: .top)
            }
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .navigationTitle("Search AO3")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Search") {
                        search.profile = draft
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .confirmationDialog("Clear the search?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear", role: .destructive) { draft.clear() }
            } message: {
                Text("Everything you've excluded stays excluded.")
            }
        }
        .onAppear { draft = search.profile }
        .themedWindow()
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 620, minHeight: 640, idealHeight: 760)
        #endif
    }

    private func ruleBinding(_ kind: TagField) -> Binding<TagRule> {
        Binding(get: { draft.rule(kind) }, set: { draft.setRule($0, kind) })
    }

    // MARK: - sections

    private var wordsSection: some View {
        LeatherSection(title: "Words") {
            TextField("Any field: titles, summaries, tags…", text: $draft.words)
            TextField("Title", text: $draft.title)
            TextField("Creator", text: $draft.creator)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
        } footer: {
            Text("AO3's search syntax works in the first field: quotes for a phrase, OR, NOT.")
        }
    }

    private var crossoverSection: some View {
        LeatherSection(title: "Crossovers") {
            Picker("Crossovers", selection: $draft.crossovers) {
                Text("Include").tag(SearchProfile.Crossovers.include)
                Text("Exclude").tag(SearchProfile.Crossovers.exclude)
                Text("Only").tag(SearchProfile.Crossovers.only)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } footer: {
            Text("A crossover is tagged with more than one fandom.")
        }
    }

    private var ratingSection: some View {
        LeatherSection("Rating") {
            Toggle("Explicit only", isOn: $draft.explicitOnly)
        }
    }

    private var workSection: some View {
        LeatherSection("The work") {
            Picker("Status", selection: $draft.completion) {
                Text("Any").tag(SearchProfile.Completion.any)
                Text("Complete").tag(SearchProfile.Completion.complete)
                Text("In progress").tag(SearchProfile.Completion.inProgress)
            }
            Picker("Updated", selection: $draft.updatedWithin) {
                Text("Any time").tag(SearchProfile.UpdatedWithin.any)
                Text("In the past week").tag(SearchProfile.UpdatedWithin.week)
                Text("In the past month").tag(SearchProfile.UpdatedWithin.month)
                Text("In the past 6 months").tag(SearchProfile.UpdatedWithin.halfYear)
                Text("In the past year").tag(SearchProfile.UpdatedWithin.year)
            }
            Toggle("Single chapter only", isOn: $draft.singleChapter)
        }
    }

    private var orderSection: some View {
        LeatherSection(title: "Order") {
            Picker("Sort by", selection: $draft.sort) {
                ForEach(AO3WorkQuery.Sort.allCases) { sort in
                    Text(sort.label).tag(sort)
                }
            }
            Picker("Direction", selection: $draft.ascending) {
                Text(draft.sort.isAlphabetical ? "Z to A" : "Highest or newest first").tag(false)
                Text(draft.sort.isAlphabetical ? "A to Z" : "Lowest or oldest first").tag(true)
            }
        } footer: {
            if draft.sort == .relevance && draft.words.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("Best match needs words to match; without them, results are sorted by date updated.")
            }
        }
    }

    private var librarySection: some View {
        LeatherSection(title: "Your library") {
            Toggle("Hide fics I already have", isOn: $draft.hideOwned)
            ExcludedAuthorsRows(authors: $draft.hiddenAuthors)
        } footer: {
            Text("Fics by excluded creators never show. AO3 can't filter creators, so Parade does.")
        }
    }

    private var resetSection: some View {
        Section {
            Button("Start Over from My Library's Fandoms") {
                draft.reset(fandomLists: search.libraryFandomLists)
            }
            Button("Clear Search", role: .destructive) { confirmClear = true }
        }
        .listRowBackground(Color.clear)
    }
}

/// A warning or category, three ways: any, wanted, never.
private struct FixedTagSection: View {
    let title: String
    let tags: [FixedTag]
    @Binding var choices: [Int: Inclusion]
    let footer: String

    var body: some View {
        LeatherSection(title: title) {
            ForEach(tags) { tag in
                // Side by side when the name fits; a long warning goes above
                // its control rather than being cut off.
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text(tag.name).fixedSize()
                        Spacer(minLength: 12)
                        picker(tag)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tag.name).fixedSize(horizontal: false, vertical: true)
                        picker(tag)
                    }
                    .padding(.vertical, 2)
                }
            }
        } footer: {
            Text(footer)
        }
    }

    private func picker(_ tag: FixedTag) -> some View {
        Picker(tag.name, selection: choice(tag)) {
            Text("Any").tag(Inclusion?.none)
            Text("Include").tag(Inclusion?.some(.include))
            Text("Exclude").tag(Inclusion?.some(.exclude))
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    private func choice(_ tag: FixedTag) -> Binding<Inclusion?> {
        Binding(get: { choices[tag.id] }, set: { choices[tag.id] = $0 })
    }
}

/// Tags of one kind the search wants, and ones it won't have, with a field
/// to add either.
private struct TagRuleSection: View {
    let kind: TagField
    @Binding var rule: TagRule
    @EnvironmentObject private var search: SearchModel
    @EnvironmentObject private var model: AppModel
    @State private var adding = ""
    @Environment(\.palette) private var palette

    var body: some View {
        LeatherSection(title: kind.title) {
            ForEach(rule.include, id: \.self) { tag in
                TagRuleRow(tag: tag, inclusion: .include, count: kind == .fandom ? search.libraryCount(of: tag) : nil) {
                    rule.include.removeAll { $0 == tag }
                }
            }
            .onDelete { rule.include.remove(atOffsets: $0) }
            ForEach(rule.exclude, id: \.self) { tag in
                TagRuleRow(tag: tag, inclusion: .exclude) {
                    rule.exclude.removeAll { $0 == tag }
                }
            }
            .onDelete { rule.exclude.remove(atOffsets: $0) }
            AddTagRow(text: $adding, prompt: "Add a \(kind.singular)", suggestions: suggestions) { name, inclusion in
                add(name, inclusion)
            }
            if kind == .fandom {
                let missing = search.unsearchedLibraryFandoms(in: profileForMissing)
                if !missing.isEmpty {
                    DisclosureGroup("From your library (\(missing.count))") {
                        ForEach(missing, id: \.name) { fandom in
                            Button { add(fandom.name, .include) } label: {
                                HStack {
                                    Image(systemName: "plus.circle").foregroundStyle(palette.rose)
                                    Text(fandom.name).lineLimit(1)
                                    Spacer()
                                    Numeral(value: fandom.count)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        switch kind {
        case .fandom:
            rule.include.isEmpty
                ? "No fandoms: all of AO3. Fics in any fandom you add; never one you exclude."
                : "Fics in any of these, and in none you exclude."
        default:
            "Fics with every \(kind.singular) you include, and none you exclude."
        }
    }

    private var profileForMissing: SearchProfile {
        var p = SearchProfile()
        p.fandoms = rule.include
        p.excludedFandoms = rule.exclude
        return p
    }

    private var suggestions: [String] { kind.suggestions(model) }

    private func add(_ name: String, _ inclusion: Inclusion) {
        let tag = TagRef(name: name)
        rule.include.removeAll { $0.isSame(as: tag) }
        rule.exclude.removeAll { $0.isSame(as: tag) }
        if inclusion == .include { rule.include.append(tag) } else { rule.exclude.append(tag) }
    }
}

/// One tag in a section: its name as AO3 has it, and whether it's wanted.
private struct TagRuleRow: View {
    let tag: TagRef
    let inclusion: Inclusion
    var count: Int?
    let remove: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: inclusion == .include ? "checkmark.circle" : "nosign")
                .foregroundStyle(inclusion == .include ? palette.gold : palette.alert)
                .accessibilityLabel(inclusion == .include ? "Include" : "Exclude")
            VStack(alignment: .leading, spacing: 2) {
                Text(tag.displayName).lineLimit(2)
                    .strikethrough(inclusion == .exclude, color: palette.inkFaint)
                if let canonical = tag.canonical, canonical.caseInsensitiveCompare(tag.name) != .orderedSame {
                    Text("from \(tag.name)").textRole(.meta).lineLimit(1)
                }
            }
            Spacer()
            if let count, count > 0 { Numeral(value: count) }
            #if os(macOS)
            // No swipe to delete on the Mac.
            RemoveButton(action: remove)
            #endif
        }
    }
}

#if os(macOS)
private struct RemoveButton: View {
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill").foregroundStyle(palette.inkFaint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove")
    }
}
#endif

/// A field to add a tag, suggesting the library's own as you type. What's
/// typed can be added as is: it's looked up on AO3 when the search runs.
private struct AddTagRow: View {
    @Binding var text: String
    let prompt: String
    let suggestions: [String]
    let add: (String, Inclusion) -> Void

    private var query: String { text.trimmingCharacters(in: .whitespaces) }

    private var matches: [String] {
        guard !query.isEmpty else { return [] }
        return Array(suggestions.lazy.filter { $0.localizedCaseInsensitiveContains(query) }.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(prompt, text: $text)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .onSubmit { commit(text, .include) }
            if !query.isEmpty {
                ForEach(matches.isEmpty ? [query] : matches, id: \.self) { name in
                    HStack {
                        Text(name).textRole(.small).lineLimit(1)
                        Spacer()
                        Button("Include") { commit(name, .include) }
                        Button("Exclude") { commit(name, .exclude) }
                    }
                    .buttonStyle(.leather)
                    .controlSize(.small)
                }
            }
        }
    }

    private func commit(_ value: String, _ inclusion: Inclusion) {
        let name = value.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        add(name, inclusion)
        text = ""
    }
}

/// Creators whose fics never show.
private struct ExcludedAuthorsRows: View {
    @Binding var authors: [String]
    @State private var adding = ""
    @Environment(\.palette) private var palette

    var body: some View {
        ForEach(authors, id: \.self) { author in
            HStack(spacing: 10) {
                Image(systemName: "nosign").foregroundStyle(palette.alert)
                Text(author)
                #if os(macOS)
                Spacer()
                RemoveButton { authors.removeAll { $0 == author } }
                #endif
            }
        }
        .onDelete { authors.remove(atOffsets: $0) }
        TextField("Exclude a creator", text: $adding)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .onSubmit {
                let name = adding.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty, !authors.contains(name) { authors.append(name) }
                adding = ""
            }
    }
}

extension AO3WorkQuery.Sort {
    /// Sorted by name, so "ascending" reads A to Z.
    var isAlphabetical: Bool { self == .title || self == .creator }
}

/// What a search is set to, in a few plain lines for the top of the results.
enum SearchSummary {
    static func lines(_ p: SearchProfile) -> [String] {
        var lines: [String] = []
        var scope: [String] = []
        switch p.fandoms.count {
        case 0: scope.append("All of AO3")
        case 1: scope.append(p.fandoms[0].displayName)
        default: scope.append("\(p.fandoms.count) fandoms")
        }
        if !p.excludedFandoms.isEmpty { scope.append("not \(list(p.excludedFandoms.map(\.displayName)))") }
        switch p.crossovers {
        case .include: break
        case .exclude: scope.append("no crossovers")
        case .only: scope.append("crossovers only")
        }
        lines.append(scope.joined(separator: " · "))

        var words: [String] = []
        let w = p.words.trimmingCharacters(in: .whitespaces)
        if !w.isEmpty { words.append("“\(w)”") }
        if !p.title.trimmingCharacters(in: .whitespaces).isEmpty { words.append("title “\(p.title)”") }
        if !p.creator.trimmingCharacters(in: .whitespaces).isEmpty { words.append("by \(p.creator)") }
        if !words.isEmpty { lines.append(words.joined(separator: " · ")) }

        var kinds: [String] = []
        if p.explicitOnly { kinds.append("Explicit") }
        for (choices, tags) in [(p.categories, FixedTag.categories), (p.warnings, FixedTag.warnings)] {
            let wanted = tags.filter { choices[$0.id] == .include }.map(\.name)
            let refused = tags.filter { choices[$0.id] == .exclude }.map(\.name)
            if !wanted.isEmpty { kinds.append(wanted.joined(separator: " or ")) }
            if !refused.isEmpty { kinds.append("no " + list(refused)) }
        }
        if !kinds.isEmpty { lines.append(kinds.joined(separator: " · ")) }

        let rules = [p.relationships, p.characters, p.freeforms]
        let wanted = rules.flatMap(\.include).map(\.displayName)
        let refused = rules.flatMap(\.exclude).map(\.displayName)
        var tags: [String] = []
        if !wanted.isEmpty { tags.append("with " + list(wanted)) }
        if !refused.isEmpty { tags.append("without " + list(refused)) }
        if !tags.isEmpty { lines.append(tags.joined(separator: " · ")) }

        var work: [String] = []
        switch p.completion {
        case .any: break
        case .complete: work.append("Complete")
        case .inProgress: work.append("In progress")
        }
        if p.singleChapter { work.append("one chapter") }
        switch p.updatedWithin {
        case .any: break
        case .week: work.append("updated this week")
        case .month: work.append("updated this month")
        case .halfYear: work.append("updated in 6 months")
        case .year: work.append("updated this year")
        }
        if p.hideOwned { work.append("not ones I have") }
        if !p.hiddenAuthors.isEmpty { work.append("\(p.hiddenAuthors.count) creator\(p.hiddenAuthors.count == 1 ? "" : "s") excluded") }
        if !work.isEmpty { lines.append(work.joined(separator: " · ")) }

        let direction = p.ascending
            ? (p.effectiveSort.isAlphabetical ? "A to Z" : "lowest first")
            : (p.effectiveSort.isAlphabetical ? "Z to A" : nil)
        lines.append("Sorted by \(p.effectiveSort.label.lowercased())" + (direction.map { ", \($0)" } ?? ""))
        return lines
    }

    /// "A", "A and B", "A, B and 3 more".
    private static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: ""
        case 1: names[0]
        case 2: "\(names[0]) and \(names[1])"
        default: "\(names[0]), \(names[1]) and \(names.count - 2) more"
        }
    }
}

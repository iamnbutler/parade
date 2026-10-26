import SwiftUI
import AO3Kit

/// AO3 search results, under a summary of what the search is set to. The
/// search itself is set up on its own page, `SearchForm`; it stays as it
/// was left until changed there.
struct SearchView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var search: SearchModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var editing = false
    #if os(macOS)
    /// The result shown in the detail column.
    @Binding var selection: Int?
    #endif

    var body: some View {
        #if os(iOS)
        NavigationStack {
            content
                .tabHeader("Search") {
                    Button("Edit Search") { editing = true }
                        .buttonStyle(.leather)
                }
                .navigationDestination(for: WorkBlurb.self) { work in
                    WorkPreview(work: work)
                }
        }
        #else
        content
        #endif
    }

    private var content: some View {
        list
            .sheet(isPresented: $editing) {
                SearchForm()
            }
            .onAppear {
                search.start(with: model)
                model.buildDetailsIndex()
            }
            .onChange(of: model.detailsIndex) { _, _ in
                search.start(with: model)
                search.refreshOwned()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { search.reloadFromDisk() }
            }
    }

    private var list: some View {
        #if os(macOS)
        List(selection: $selection) { rows }
            .leatherList()
            .overlay { emptyState }
        #else
        List { rows }
            .leatherList()
            .overlay { emptyState }
            .refreshable { search.restart() }
        #endif
    }

    @ViewBuilder
    private var rows: some View {
            Section {
                SearchSummaryCard { editing = true }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                summaryLine
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            Section {
                ForEach(search.works) { work in
                    row(work)
                        .onAppear { search.loadMoreIfNeeded(after: work) }
                }
                .leatherRows()
                footer
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
    }

    @ViewBuilder
    private func row(_ work: WorkBlurb) -> some View {
        #if os(iOS)
        NavigationLink(value: work) { BlurbRow(work: work) }
        #else
        BlurbRow(work: work)
            .tag(work.id)
        #endif
    }

    /// "12,408 fics in 6 fandoms" — and anything holding the search up.
    @ViewBuilder
    private var summaryLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let total = search.total, search.phase == .loaded {
                Text(countLine(total)).textRole(.meta)
            }
            if !search.resolving.isEmpty {
                Text("Looking up \(search.resolving.count) tag\(search.resolving.count == 1 ? "" : "s") on AO3…")
                    .textRole(.meta)
            }
            if let wait = waitLine {
                Text(wait).textRole(.meta)
            }
        }
    }

    private func countLine(_ total: Int) -> String {
        let fics = "\(total.formatted()) fic\(total == 1 ? "" : "s")"
        let hidden = search.fetched.count - search.works.count
        return hidden > 0 ? "\(fics) · \(hidden) hidden so far" : fics
    }

    /// Why nothing's arriving, when AO3 asked us to wait.
    private var waitLine: String? {
        switch search.schedulerState {
        case .waiting(let until) where until.timeIntervalSinceNow > 5:
            "AO3 asked us to slow down — continuing at \(until.formatted(date: .omitted, time: .shortened))"
        case .paused(let until):
            "Paused until \(until.formatted(date: .omitted, time: .shortened)) — AO3 is busy"
        default:
            nil
        }
    }

    @ViewBuilder
    private var footer: some View {
        if search.isLoadingMore {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Finding more fics…").textRole(.meta)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        } else if search.hitResultCap {
            Text("AO3 shows at most 100,000 fics. Narrow the search to see more.")
                .textRole(.meta)
                .frame(maxWidth: .infinity)
        } else if search.phase == .loaded, !search.hasMore, !search.works.isEmpty {
            Fleuron().frame(maxWidth: .infinity).padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch search.phase {
        case .loading where search.works.isEmpty:
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text("Searching AO3…").textRole(.dek)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        case .failed(let message):
            EmptyPage(drawing: "EmptyBrowse", title: "AO3 didn't answer", message: message) {
                Button("Try Again") { search.restart() }
            }
        case .loaded where search.works.isEmpty:
            EmptyPage(drawing: "EmptyBrowse", title: "Nothing matches",
                      message: search.fetched.isEmpty
                        ? "Try fewer words or tags, or more fandoms."
                        : "Everything on this page is hidden or already yours.") {
                if search.hasMore {
                    Button("Look Further") {
                        if let last = search.fetched.last { search.loadMoreIfNeeded(after: last, force: true) }
                    }
                }
            }
        case .idle:
            if !search.profile.seeded {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text("Reading your library's fandoms…").textRole(.dek)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        default:
            EmptyView()
        }
    }
}

/// One AO3 work as a search lists it: title, who and where, the facts, the
/// start of the summary, and the first few tags.
struct BlurbRow: View {
    let work: WorkBlurb
    @EnvironmentObject private var search: SearchModel
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(work.title).textRole(.rowTitle).lineLimit(2)
                Spacer(minLength: 4)
                OwnedMark(work: work)
            }
            Text(byline).textRole(.meta).lineLimit(1)
            Text(facts).textRole(.meta).lineLimit(1)
                .foregroundStyle(palette.inkFaint)
            if let summary = work.summary {
                Text(summary)
                    .textRole(.summary)
                    .lineLimit(3)
                    .padding(.top, 2)
            }
            if !tagLine.isEmpty {
                Text(tagLine)
                    .font(.reading(13, relativeTo: .caption))
                    .foregroundStyle(palette.inkFaint)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu { BlurbActions(work: work) }
        .swipeActions(edge: .leading) {
            if search.saving.contains(work.id) || search.owned[work.id] != nil {
            } else {
                Button { search.save(work, toRead: true, model: model) } label: {
                    Label("To Read", systemImage: "bookmark")
                }
                .tint(SwipeTint.favorite)
            }
        }
        .swipeActions(edge: .trailing) {
            Button { search.hide(author: work.authors.first ?? "") } label: {
                Label("Hide Author", systemImage: "eye.slash")
            }
            .tint(SwipeTint.remove)
        }
    }

    private var byline: String {
        let authors = work.authors.joined(separator: " & ")
        let fandoms = work.fandoms.prefix(2).joined(separator: ", ") + (work.fandoms.count > 2 ? " +\(work.fandoms.count - 2)" : "")
        return fandoms.isEmpty ? "by \(authors)" : "by \(authors) · \(fandoms)"
    }

    private var facts: String {
        WorkFacts.line(work)
    }

    private var tagLine: String {
        let tags = work.relationships + work.freeforms
        guard !tags.isEmpty else { return "" }
        let shown = tags.prefix(4).joined(separator: " · ")
        return tags.count > 4 ? shown + " · +\(tags.count - 4)" : shown
    }
}

/// "In library", "To Read", or saving — for a work you already have.
struct OwnedMark: View {
    let work: WorkBlurb
    @EnvironmentObject private var search: SearchModel
    @Environment(\.palette) private var palette

    var body: some View {
        if search.saving.contains(work.id) {
            ProgressView().controlSize(.small)
        } else if let toRead = search.owned[work.id] {
            Text(toRead ? "To Read" : "In library")
                .font(.reading(12, relativeTo: .caption, italic: true))
                .foregroundStyle(palette.gold)
                .fixedSize()
        }
    }
}

/// The facts line of a work: "Explicit · Complete · 84k words · 23/23 ch · 4.1k kudos · 19 Dec 2025".
enum WorkFacts {
    static func line(_ work: WorkBlurb) -> String {
        var parts: [String] = []
        if let rating = work.rating, rating != "Not Rated" { parts.append(short(rating)) }
        if let complete = work.isComplete { parts.append(complete ? "Complete" : "In progress") }
        if let words = work.words { parts.append("\(compact(words)) words") }
        if let chapters = work.chapters { parts.append("\(chapters) ch") }
        if let kudos = work.kudos { parts.append("\(compact(kudos)) kudos") }
        if let date = work.date { parts.append(date) }
        return parts.joined(separator: " · ")
    }

    private static func short(_ rating: String) -> String {
        switch rating {
        case "General Audiences": "General"
        case "Teen And Up Audiences": "Teen"
        default: rating
        }
    }

    /// 84,213 → "84k"; 1,250 → "1.2k"; 980 → "980".
    static func compact(_ n: Int) -> String {
        n.formatted(.number.notation(.compactName).precision(.significantDigits(1...2)))
            .lowercased()
    }
}

/// Save, open, and hide: the long-press menu and the preview's actions share these.
struct BlurbActions: View {
    let work: WorkBlurb
    @EnvironmentObject private var search: SearchModel
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if search.owned[work.id] == nil {
            Button { search.save(work, toRead: true, model: model) } label: {
                Label("Save to To Read", systemImage: "bookmark")
            }
            Button { search.save(work, toRead: false, model: model) } label: {
                Label("Save to Library", systemImage: "books.vertical")
            }
            .disabled(search.saving.contains(work.id))
        }
        Link(destination: work.url) {
            Label("Open on AO3", systemImage: "safari")
        }
        Divider()
        ForEach(work.authors.filter { $0 != "Anonymous" }, id: \.self) { author in
            Button { search.hide(author: author) } label: {
                Label("Hide \(author)", systemImage: "eye.slash")
            }
        }
    }
}

/// What the search is set to, at the top of the results: a few plain lines
/// and the way into the form.
private struct SearchSummaryCard: View {
    let edit: () -> Void
    @EnvironmentObject private var search: SearchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(SearchSummary.lines(search.profile).enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .textRole(index == 0 ? .rowTitle : .meta)
                        .lineLimit(2)
                }
            }
            Button(action: edit) {
                Label("Edit Search", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.leatherProminent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .debossed(cornerRadius: 12)
    }
}

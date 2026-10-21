import SwiftUI
import AO3Kit

/// Searching and browsing AO3 itself. AO3 has no API: each page is one
/// fetch of the site's own listing, made only when the reader asks — on
/// submit, a sort change, a tag tapped, or More — never ahead of them.
@MainActor
final class AO3Browser: ObservableObject {
    @Published private(set) var query: AO3WorkQuery?
    @Published private(set) var works: [WorkBlurb] = []
    @Published private(set) var total: Int?
    @Published private(set) var hasNextPage = false
    @Published private(set) var isLoading = false
    @Published private(set) var failure: String?
    /// Earlier listings, for Back after following a tag.
    @Published private(set) var history: [AO3WorkQuery] = []
    /// Works saved from these results this session (before the library
    /// index catches up).
    @Published var saved: Set<Int> = []

    /// For the next search; an open listing carries its own.
    @Published private(set) var sort: AO3WorkQuery.Sort = .relevance
    @Published private(set) var completeOnly = false

    /// The open listing's sort, or the next search's.
    var shownSort: AO3WorkQuery.Sort { query?.sort ?? sort }
    var shownCompleteOnly: Bool { query?.completeOnly ?? completeOnly }

    func search(_ text: String, model: AppModel) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        history = []
        run(AO3WorkQuery(source: .search(trimmed), sort: sort, completeOnly: completeOnly), model: model)
    }

    func openTag(_ name: String, model: AppModel) {
        if let query { history.append(query) }
        // A tag listing has no relevance order; most recent first.
        run(AO3WorkQuery(source: .tag(name), sort: sort == .relevance ? .updated : sort,
                         completeOnly: completeOnly), model: model)
    }

    func back(model: AppModel) {
        guard let previous = history.popLast() else { return }
        run(previous, model: model)
    }

    /// Re-runs the open listing (if any) in a new order or filter.
    func set(sort: AO3WorkQuery.Sort? = nil, completeOnly: Bool? = nil, model: AppModel) {
        if let sort { self.sort = sort }
        if let completeOnly { self.completeOnly = completeOnly }
        guard var q = query else { return }
        q.sort = self.sort
        // A tag listing has no relevance order.
        if case .tag = q.source, q.sort == .relevance { q.sort = .updated }
        q.completeOnly = self.completeOnly
        q.page = 1
        run(q, model: model)
    }

    func loadMore(model: AppModel) {
        guard var q = query, hasNextPage, !isLoading else { return }
        q.page += 1
        Task { await fetch(q, model: model, appending: true) }
    }

    private func run(_ q: AO3WorkQuery, model: AppModel) {
        guard !isLoading else { return }
        query = q
        works = []
        total = nil
        hasNextPage = false
        Task { await fetch(q, model: model, appending: false) }
    }

    private func fetch(_ q: AO3WorkQuery, model: AppModel, appending: Bool) async {
        isLoading = true
        failure = nil
        defer { isLoading = false }
        do {
            let page = try await model.ao3Works(q)
            query = q
            // A work can slide onto the next page while you read; show it once.
            let known = Set(works.map(\.id))
            works = (appending ? works : []) + page.works.filter { !appending || !known.contains($0.id) }
            total = page.total ?? total
            hasNextPage = page.hasNextPage
        } catch AO3Error.rateLimited(let retry) {
            failure = retry.map { "AO3 asked Parade to slow down. Try again in \($0) seconds." }
                ?? "AO3 is busy or asked Parade to slow down. Try again in a minute."
        } catch {
            failure = "Couldn't reach AO3: \(error.localizedDescription)"
        }
    }

    var title: String {
        switch query?.source {
        case .search(let text): text.quoted
        case .tag(let name): name
        case nil: "Find on AO3"
        }
    }

    var subtitle: String? {
        guard query != nil else { return nil }
        if let total { return "\(total.formatted()) work\(total == 1 ? "" : "s") on AO3" }
        return isLoading ? "Asking AO3…" : nil
    }
}

/// The search page: a field that searches on Return, sort and filter, and
/// the results. On the Mac `selection` drives the detail column; on iOS
/// rows push the work's page.
struct AO3SearchPage: View {
    @ObservedObject var browser: AO3Browser
    var selection: Binding<Int?>?
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @State private var text = ""

    var body: some View {
        List(selection: selection) {
            PageHeader(title: browser.title, subtitle: browser.subtitle)
            controls
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            if let failure = browser.failure {
                Text(failure)
                    .textRole(.dek)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            ForEach(browser.works) { work in
                row(work)
            }
            .leatherRows()
            footer
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .leatherList()
        .overlay {
            if browser.query == nil {
                EmptyPage(
                    drawing: "EmptyBrowse",
                    title: "Find on AO3",
                    message: "Search the Archive by title, author, fandom or tag. Nothing is fetched until you press Return.")
                .allowsHitTesting(false)
                .padding(.top, 120)
            }
        }
    }

    @ViewBuilder
    private func row(_ work: WorkBlurb) -> some View {
        #if os(iOS)
        NavigationLink(value: work) {
            BlurbRow(work: work, browser: browser)
        }
        #else
        BlurbRow(work: work, browser: browser).tag(work.id)
        #endif
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(palette.inkFaint)
                TextField("Search AO3…", text: $text)
                    .textFieldStyle(.plain)
                    .font(.reading(16, relativeTo: .body))
                    .onSubmit { browser.search(text, model: model) }
                    .submitLabel(.search)
                    #if os(iOS)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    #endif
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .debossed(cornerRadius: 10)
            HStack(spacing: 8) {
                if !browser.history.isEmpty {
                    Button {
                        browser.back(model: model)
                    } label: {
                        Label("Back", systemImage: "chevron.backward")
                    }
                    .buttonStyle(.leather)
                }
                Menu {
                    Picker("Sort by", selection: Binding(
                        get: { browser.shownSort },
                        set: { browser.set(sort: $0, model: model) })) {
                        ForEach(AO3WorkQuery.Sort.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(browser.shownSort.label, systemImage: "arrow.up.arrow.down")
                }
                .menuStyle(.button)
                .buttonStyle(.leather)
                .fixedSize()
                Toggle("Complete only", isOn: Binding(
                    get: { browser.shownCompleteOnly },
                    set: { browser.set(completeOnly: $0, model: model) }))
                    .toggleStyle(.button)
                    .buttonStyle(LeatherButtonStyle(prominent: browser.shownCompleteOnly))
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if browser.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        } else if browser.hasNextPage {
            // A button, not infinite scroll: each page is a request to AO3.
            Button("More results") { browser.loadMore(model: model) }
                .buttonStyle(.leather)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        } else if !browser.works.isEmpty {
            Fleuron().padding(.vertical, 16)
        } else if browser.query != nil, browser.failure == nil {
            Text("Nothing on AO3 matches. Try fewer words.")
                .textRole(.dek)
                .padding(.vertical, 16)
        }
    }
}

/// A result: title, author, fandom, the numbers, and the summary's start.
struct BlurbRow: View {
    let work: WorkBlurb
    @ObservedObject var browser: AO3Browser
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(work.title).textRole(.rowTitle).lineLimit(2)
                if browser.saved.contains(work.id) || model.libraryItem(workID: work.id) != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.gold)
                        .accessibilityLabel("In your library")
                }
            }
            Text("by \(work.authors.joined(separator: " & "))\(work.fandoms.first.map { " · \($0)" } ?? "")")
                .textRole(.meta)
                .lineLimit(1)
            if let summary = work.summary {
                // One run of text: a summary that opens with short lines
                // would otherwise show only the first.
                Text(summary.replacingOccurrences(of: #"\s*\n+\s*"#, with: " ", options: .regularExpression))
                    .textRole(.summary)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
            Text(BlurbFacts.line(work))
                .textRole(.meta)
                .lineLimit(1)
                .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }
}

enum BlurbFacts {
    /// "Teen · Complete · 2,407 words · 1/1 · ♥ 120,019"
    static func line(_ w: WorkBlurb) -> String {
        [
            w.rating.map(shortRating),
            w.isComplete.map { $0 ? "Complete" : "In progress" },
            w.words.map { "\($0.formatted()) words" },
            w.chapters.map { "\($0) ch." },
            w.kudos.map { "♥ \($0.formatted())" },
        ].compactMap { $0 }.joined(separator: " · ")
    }

    static func shortRating(_ r: String) -> String {
        switch r {
        case "General Audiences": "General"
        case "Teen And Up Audiences": "Teen"
        case "Not Rated": "Not rated"
        default: r
        }
    }
}

/// A result's own page: what AO3 shows of it, Download (or Read, once it's
/// in the library), and its tags, each a door to more like it.
struct BlurbDetailView: View {
    let work: WorkBlurb
    @ObservedObject var browser: AO3Browser
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.readFic) private var readFic
    @Environment(\.dismiss) private var dismiss
    @State private var downloading = false

    private var libraryItem: LibraryItem? { model.libraryItem(workID: work.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    if let fandom = work.fandoms.first {
                        Text(fandom).textRole(.runningHead).lineLimit(1)
                    }
                    Text(work.title)
                        .textRole(.title)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("by \(work.authors.joined(separator: " & "))").textRole(.dek)
                    ForEach(work.series, id: \.self) { Text($0).textRole(.meta) }
                }
                actions
                if let summary = work.summary {
                    StitchedCard(label: "The summary") {
                        Text(summary)
                            .textRole(.body)
                            .textSelection(.enabled)
                    }
                }
                Text(stats).textRole(.meta)
                Hairline()
                facts
                tagField("Fandom", work.fandoms)
                tagField("Relationships", work.relationships)
                tagField("Characters", work.characters)
                tagField("Tags", work.freeforms)
                Fleuron().padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 40)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .leatherBackground()
    }

    private var actions: some View {
        FlowLayout(spacing: 8) {
            if let item = libraryItem {
                Button {
                    readFic?(item)
                } label: {
                    Label("Read", systemImage: "book")
                }
                .buttonStyle(.leatherProminent)
                .disabled(!item.isDownloaded)
            } else {
                Button {
                    Task {
                        downloading = true
                        await model.download(workID: work.id)
                        downloading = false
                        browser.saved.insert(work.id)
                    }
                } label: {
                    if downloading {
                        Label("Downloading…", systemImage: "arrow.down.circle")
                    } else if browser.saved.contains(work.id) {
                        Label("Saved", systemImage: "checkmark.circle")
                    } else {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                }
                .buttonStyle(.leatherProminent)
                .disabled(downloading || model.isWorking || browser.saved.contains(work.id))
            }
            Link(destination: work.url) {
                Label("AO3", systemImage: "safari")
            }
            .buttonStyle(.leather)
        }
    }

    private var stats: String {
        [
            work.words.map { "\($0.formatted()) words" },
            work.chapters.map { "\($0) chapters" },
            work.kudos.map { "\($0.formatted()) kudos" },
            work.hits.map { "\($0.formatted()) hits" },
            work.date.map { "updated \($0)" },
        ].compactMap { $0 }.joined(separator: " · ")
    }

    private var facts: some View {
        let rows = [
            ("Rating", work.rating.map { [$0] } ?? []),
            ("Warnings", work.warnings),
            ("Category", work.categories),
            ("Language", work.language.map { [$0] } ?? []),
        ].filter { !$0.1.isEmpty }
        return Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
            ForEach(rows, id: \.0) { label, values in
                GridRow {
                    Text(label).textRole(.kicker)
                    Text(values.joined(separator: ", ")).textRole(.body)
                }
            }
        }
    }

    @ViewBuilder
    private func tagField(_ label: String, _ values: [String]) -> some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(label).textRole(.kicker)
                FlowLayout(spacing: 6) {
                    ForEach(values, id: \.self) { value in
                        Button {
                            browser.openTag(value, model: model)
                            #if os(iOS)
                            dismiss()
                            #endif
                        } label: {
                            Chip(text: value)
                        }
                        .buttonStyle(.plain)
                        .help("More works tagged \(value.quoted) on AO3")
                    }
                }
            }
        }
    }
}

#if os(iOS)
/// Pushes the AO3 search page (from Browse's toolbar).
struct AO3SearchRoute: Hashable {}

extension View {
    /// The AO3 search page and its works, on a NavigationStack.
    func ao3SearchDestinations(_ browser: AO3Browser) -> some View {
        self
            .navigationDestination(for: AO3SearchRoute.self) { _ in
                AO3SearchPage(browser: browser)
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .navigationDestination(for: WorkBlurb.self) { work in
                BlurbDetailView(work: work, browser: browser)
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
            }
    }
}
#endif

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
                if let details, details.workURL == nil {
                    AO3LinkFinder(item: item)
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
    }

    /// The root presents the reader (the window on the Mac, a full-screen
    /// cover on iOS), so it outlives this page being rebuilt.
    private func read() {
        readFic?(item)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let head = runningHead ?? (model.isToRead(item) ? "To Read" : details?.fandoms.first) {
                Text(head).textRole(.runningHead).lineLimit(1)
            }
            Text(details?.title ?? item.title)
                .textRole(.title)
                .fixedSize(horizontal: false, vertical: true)
            byline
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

    /// "by A & B", each author opening their fics.
    private var byline: some View {
        FlowLayout(spacing: 5) {
            Text("by").textRole(.dek)
            ForEach(Array(authors.enumerated()), id: \.offset) { i, author in
                if i > 0 { Text("&").textRole(.dek) }
                FacetLink(facet: FacetSelection(kind: .author, name: author)) {
                    Text(author)
                        .textRole(.dek)
                        .foregroundStyle(palette.rose)
                }
            }
        }
    }

    /// The EPUB's authors; before it's read, the folder's ("A & B").
    private var authors: [String] {
        if let authors = details?.authors, !authors.isEmpty { return authors }
        return item.author.components(separatedBy: " & ")
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
            if model.isToRead(item) {
                Button {
                    Task { await model.addToLibrary(item) }
                } label: {
                    Label("Add to Library", systemImage: "books.vertical")
                }
                .buttonStyle(.leather)
                .disabled(!item.isDownloaded)
                .help("Move this fic from To Read into your library")
            }
            // Always available; prominent when a check found an update.
            updateButton
                .buttonStyle(LeatherButtonStyle(prominent: model.hasUpdate(item)))
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
            VStack(alignment: .leading, spacing: 6) {
                Text(authors.count == 1 ? "Author" : "Authors").textRole(.kicker)
                FacetChips(kind: .author, values: authors)
            }
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
    /// gold labels, chips that open every fic sharing the value.
    private func facts(_ d: WorkDetails) -> some View {
        let rows: [(String, FacetSelection.Kind, [String])] = [
            ("Rating", .rating, d.rating), ("Warnings", .warning, d.warnings), ("Category", .category, d.categories),
        ].filter { !$0.2.isEmpty }
        return Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
            ForEach(rows, id: \.0) { label, kind, values in
                GridRow {
                    Text(label).textRole(.kicker)
                    FacetChips(kind: kind, values: values)
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

/// For a fic whose EPUB has no AO3 link (downloaded elsewhere): finds the
/// work on AO3 by title and author, and on a choice re-downloads AO3's own
/// export, which brings the link, tags, summary and series with it.
private struct AO3LinkFinder: View {
    let item: LibraryItem
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @State private var candidates: [WorkBlurb]?
    @State private var searching = false
    @State private var failure: String?
    @State private var pasted = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Not linked to AO3").textRole(.kicker)
            Text("This copy came from outside Parade, so it has no AO3 link, tags or series. Find the work on AO3 and Parade will fetch AO3's own copy; this one goes to Backups.")
                .textRole(.meta)
                .fixedSize(horizontal: false, vertical: true)
            if let candidates {
                if candidates.isEmpty {
                    Text("AO3's search found nothing by that title and author.").textRole(.dek)
                }
                ForEach(candidates.prefix(5)) { work in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(work.title).textRole(.rowTitle)
                            Text(byline(work))
                                .textRole(.meta)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button("This one") {
                            Task { await model.link(item, toWork: work.id) }
                        }
                        .buttonStyle(LeatherButtonStyle(prominent: work.matches(title: item.title, author: item.author)))
                        .disabled(model.isWorking)
                    }
                    .padding(.vertical, 4)
                }
            } else if let failure {
                Text(failure).textRole(.dek)
            }
            if candidates?.isEmpty == true || failure != nil {
                // AO3's search misses some works (renamed, anonymous, odd
                // titles); a link always finds it.
                HStack(spacing: 8) {
                    TextField("Or paste the work's AO3 link", text: $pasted)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .onSubmit { linkPasted() }
                    Button("Link") { linkPasted() }
                        .buttonStyle(.leather)
                        .disabled(pastedWorkID == nil || model.isWorking)
                }
            }
            if candidates == nil || candidates?.isEmpty == true {
                Button {
                    Task { await search() }
                } label: {
                    if searching {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Searching AO3…") }
                    } else {
                        Label(candidates == nil && failure == nil ? "Find on AO3" : "Search Again",
                              systemImage: "magnifyingglass")
                    }
                }
                .buttonStyle(.leather)
                .disabled(searching || model.isWorking)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .debossed(cornerRadius: 12)
    }

    /// "by taliiaa · Heated Rivalry (TV) · 1,429 words"
    private func byline(_ work: WorkBlurb) -> String {
        var parts = ["by " + work.authors.joined(separator: " & ")]
        if let fandom = work.fandoms.first { parts.append(fandom) }
        if let words = work.words { parts.append("\(words.formatted()) words") }
        return parts.joined(separator: " · ")
    }

    private var pastedWorkID: Int? {
        if case .work(let id) = AO3Link(text: pasted) { return id }
        return nil
    }

    private func linkPasted() {
        guard let id = pastedWorkID, !model.isWorking else { return }
        Task { await model.link(item, toWork: id) }
    }

    private func search() async {
        searching = true
        failure = nil
        candidates = nil
        defer { searching = false }
        do {
            candidates = try await model.ao3Candidates(for: item)
        } catch {
            failure = "Couldn't search AO3: \(error.localizedDescription)"
        }
    }
}

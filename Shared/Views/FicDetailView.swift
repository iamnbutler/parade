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
    /// The latest earlier version of this fic, if one is kept.
    @State private var earlier: KeptCopy?

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
                if let details, details.workID == nil {
                    // Unlinked: linking is the next thing to do here.
                    AO3LinkFinder(item: item, linkedWorkID: nil)
                }
                if let earlier, earlier.home.standardizedFileURL.path == item.url.standardizedFileURL.path {
                    EarlierVersion(item: item, backup: earlier)
                }
                if let details {
                    statsRow(details)
                    Hairline()
                    metadata(details)
                    if let workID = details.workID {
                        // Rare: pointing a fic at a different work.
                        AO3LinkFinder(item: item, linkedWorkID: workID)
                    }
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
        // On the page, which is always there: a .task on a view that may
        // render nothing (the row before its backup loads) never runs.
        // Again after a restore or update (the file's date changes), and
        // when the Restore page's lists change.
        .task(id: "\(item.id)|\(item.date.timeIntervalSince1970)|\(model.recentBackups.count)") {
            earlier = await model.backups(of: item).first
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
                Text("In \(collections.joined(separator: ", "))")
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
            Button("Read", action: read)
            .buttonStyle(.leatherProminent)
            .disabled(!item.isDownloaded)
            .help("Read this fic in Parade")
            if model.isToRead(item) {
                Button("Add to Library") {
                    Task { await model.addToLibrary(item) }
                }
                .buttonStyle(.leather)
                .disabled(!item.isDownloaded)
                .help("Move this fic from To Read into your library")
            }
            // Always available; prominent when a check found an update.
            updateButton
                .buttonStyle(LeatherButtonStyle(prominent: model.hasUpdate(item)))
            if let url = details?.workURL {
                Link("AO3", destination: url)
                .buttonStyle(.leather)
            } else if let url = details?.sourceURL {
                Link("Ellipsus", destination: url)
                .buttonStyle(.leather)
            }
            Button(model.isFavorite(item) ? "Favorited" : "Favorite") {
                model.toggleFavorite(item)
            }
            .buttonStyle(.leather)
            Menu {
                CollectionMenuItems(item: item, showNewCollection: $showNewCollection)
            } label: {
                Text("Collections")
            }
            .menuStyle(.button)
            .buttonStyle(.leather)
            .fixedSize()
        }
    }

    private var updateButton: some View {
        Button("Update") {
            Task { await model.update(item) }
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

/// The version an update replaced, when there's one from the last 30 days:
/// a shortcut to the same restore as Settings › Restore.
private struct EarlierVersion: View {
    let item: LibraryItem
    let backup: KeptCopy
    @EnvironmentObject private var model: AppModel
    @State private var confirming = EarlierVersion.debugConfirms

    private static var debugConfirms: Bool {
        #if DEBUG
        DebugScreen.variant == "restore"
        #else
        false
        #endif
    }

    /// "backed up 2 days ago · 152 kB".
    private var facts: String {
        "\(backup.date.formatted(.relative(presentation: .named)))"
            + (backup.size.map { " · " + Int64($0).formatted(.byteCount(style: .file)) } ?? "")
    }

    var body: some View {
        HStack(spacing: 12) {
            // One line where it fits; on a phone, two clean lines rather
            // than "· 152 kB" wrapped onto a line of its own.
            ViewThatFits(in: .horizontal) {
                Text("Earlier version, " + facts).lineLimit(1)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Earlier version")
                    Text(facts)
                }
            }
            .textRole(.meta)
            Spacer()
            Button("Restore") { confirming = true }
                .buttonStyle(.leather)
                .disabled(model.isWorking)
                .help("Put the earlier version back; this one is kept as a backup")
        }
        .confirmationDialog("Restore the earlier version of \(item.title.quoted)?",
                            isPresented: $confirming, titleVisibility: .visible) {
            Button("Restore") { Task { await model.restore(backup) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The copy here now is kept as a backup, so you can switch back.")
        }
    }
}

/// For a fic whose EPUB has no AO3 link (downloaded elsewhere): finds the
/// work on AO3 by title and author, or takes a pasted link, and re-downloads
/// AO3's own export, which brings the link, tags, summary and series with it.
/// A fic already linked shows its work and can be pointed at another.
private struct AO3LinkFinder: View {
    let item: LibraryItem
    /// The AO3 work the EPUB links to now, if any.
    let linkedWorkID: Int?
    @State private var changing = AO3LinkFinder.debugChanging
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @State private var candidates: [WorkBlurb]?
    @State private var searching = false
    @State private var failure: String?
    @State private var pasted = ""

    var body: some View {
        if linkedWorkID != nil, !changing {
            Button("Change AO3 Link…") { changing = true }
                .buttonStyle(.leather)
                .disabled(model.isWorking)
        } else {
            finder
        }
    }

    private static var debugChanging: Bool {
        #if DEBUG
        DebugScreen.opensChangeLink
        #else
        false
        #endif
    }

    private var finder: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(linkedWorkID == nil ? "Not linked to AO3" : "Change the AO3 link").textRole(.kicker)
            Text(linkedWorkID == nil
                 ? "Linking brings in AO3's copy, with its tags and series. This copy goes to Restore."
                 : "Parade downloads that work's copy. This one goes to Restore.")
                .textRole(.meta)
                .fixedSize(horizontal: false, vertical: true)
            pasteField
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
                            Task {
                                if await model.link(item, toWork: work.id) { changing = false }
                            }
                        }
                        .buttonStyle(LeatherButtonStyle(prominent: work.matches(title: item.title, author: item.author)))
                        .disabled(model.isWorking)
                    }
                    .padding(.vertical, 4)
                }
            } else if let failure {
                Text(failure).textRole(.dek)
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

    /// A link always finds the work, even where AO3's search misses it
    /// (renamed, anonymous, odd titles) — and skips the search.
    private var pasteField: some View {
        HStack(spacing: 8) {
            TextField("Paste the work's AO3 link", text: $pasted)
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
            if linkedWorkID != nil {
                Button("Cancel") { changing = false }
                    .buttonStyle(.leather)
            }
        }
    }

    /// "by taliiaa · Heated Rivalry (TV) · 1,429 words"
    private func byline(_ work: WorkBlurb) -> String {
        var parts = ["by " + work.authors.joined(separator: " & ")]
        if let fandom = work.fandoms.first { parts.append(fandom) }
        if let words = work.words { parts.append("\(words.formatted()) words") }
        return parts.joined(separator: " · ")
    }

    private var pastedWorkID: Int? {
        // An ao3saver or Wayback link names the work too: Parade still
        // fetches AO3's own export.
        guard let id = AO3Link(text: pasted)?.workID, id != linkedWorkID else { return nil }
        return id
    }

    private func linkPasted() {
        guard let id = pastedWorkID, !model.isWorking else { return }
        Task {
            if await model.link(item, toWork: id) { changing = false }
        }
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

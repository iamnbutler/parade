import SwiftUI

extension View {
    /// A library filter field with history: tap it for recent searches; type
    /// and it also suggests the library's own fandoms, ships and tags.
    func ficSearch(text: Binding<String>, prompt: String) -> some View {
        modifier(FicSearch(text: text, prompt: prompt))
    }
}

private struct FicSearch: ViewModifier {
    @Binding var text: String
    let prompt: String
    @EnvironmentObject private var model: AppModel

    func body(content: Content) -> some View {
        content
            #if os(iOS)
            .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
            .barHidesOnScrollDown(unless: !text.isEmpty)
            #else
            .searchable(text: $text, prompt: prompt)
            #endif
            .searchSuggestions { suggestions }
            .onSubmit(of: .search) { model.rememberSearch(text) }
            // Most people never press Search: a query left alone for a
            // moment counts.
            .task(id: text) {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                model.rememberSearch(text)
            }
    }

    private static func symbol(_ kind: AppModel.SearchTerm.Kind) -> String {
        switch kind {
        case .author: "person"
        case .title: "book.closed"
        case .tag: "tag"
        }
    }

    @ViewBuilder
    private var suggestions: some View {
        let query = text.trimmingCharacters(in: .whitespaces)
        if query.isEmpty {
            if !model.recentSearches.isEmpty {
                Section("Recent") {
                    ForEach(model.recentSearches, id: \.self) { recent in
                        Label(recent, systemImage: "clock.arrow.circlepath")
                            .searchCompletion(recent)
                    }
                }
            }
        } else {
            let recents = model.recentSearches
                .filter { $0.localizedCaseInsensitiveContains(query) && $0.caseInsensitiveCompare(query) != .orderedSame }
                .prefix(3)
            ForEach(Array(recents), id: \.self) { recent in
                Label(recent, systemImage: "clock.arrow.circlepath")
                    .searchCompletion(recent)
            }
            let terms = model.searchVocabulary
                .lazy
                .filter { $0.text.localizedCaseInsensitiveContains(query) && $0.text.caseInsensitiveCompare(query) != .orderedSame }
                .prefix(6)
            ForEach(Array(terms), id: \.self) { term in
                Label(term.text, systemImage: Self.symbol(term.kind))
                    .searchCompletion(term.text)
            }
        }
    }
}

#if os(iOS)
extension View {
    /// The navigation bar (and the search field in it) slides away while
    /// the list scrolls down and comes back the moment it scrolls up — as
    /// in Safari — so search is never a trip back to the top. Always shown
    /// near the top, and while `pinned` (a search in progress). iOS 18;
    /// earlier, the bar just stays.
    func barHidesOnScrollDown(unless pinned: Bool) -> some View {
        modifier(BarHidesOnScrollDown(pinned: pinned))
    }
}

private struct BarHidesOnScrollDown: ViewModifier {
    let pinned: Bool
    @State private var hidden = false
    /// Per-frame bookkeeping in a plain object: changing it doesn't redraw.
    @State private var track = ScrollTrack()

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollGeometryChange(for: ScrollSample.self) { geo in
                    ScrollSample(y: geo.contentOffset.y, inset: geo.contentInsets.top)
                } action: { old, new in
                    guard let hide = track.decide(old: old, new: new, now: Date()) else { return }
                    if hide != hidden {
                        track.flipped(at: Date())
                        withAnimation(.easeInOut(duration: 0.22)) { hidden = hide }
                    }
                }
                .toolbarVisibility(hidden && !pinned ? .hidden : .visible, for: .navigationBar)
        } else {
            content
        }
    }
}

private struct ScrollSample: Equatable {
    var y: CGFloat
    var inset: CGFloat
}

/// Decides hide/show from scrolling — only from the reader's own scrolling.
/// Showing or hiding the bar changes the list's insets and offset, which
/// looks like a scroll the other way; reacting to that flipped the bar back
/// and forth forever. So: frames where the inset moved are ignored, nothing
/// is decided while the bar is still sliding, and a direction has to hold
/// for a short distance before it counts.
private final class ScrollTrack {
    private var travel: CGFloat = 0
    private var settledAt = Date.distantPast

    func decide(old: ScrollSample, new: ScrollSample, now: Date) -> Bool? {
        guard old.inset == new.inset, now >= settledAt else {
            travel = 0
            return nil
        }
        if new.y + new.inset < 60 { return false }  // at the top: always shown
        let delta = new.y - old.y
        travel = (delta > 0) == (travel > 0) ? travel + delta : delta
        if travel > 24 { return true }
        if travel < -24 { return false }
        return nil
    }

    func flipped(at now: Date) {
        travel = 0
        settledAt = now.addingTimeInterval(0.35)
    }
}
#endif

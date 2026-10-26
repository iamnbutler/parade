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
            // Always showing: hidden until scrolled back to the top meant a
            // trip up through hundreds of fics to search.
            .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
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

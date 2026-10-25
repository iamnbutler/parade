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
            .searchable(text: $text, prompt: prompt)
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
            let tags = model.searchVocabulary
                .lazy
                .filter { $0.localizedCaseInsensitiveContains(query) && $0.caseInsensitiveCompare(query) != .orderedSame }
                .prefix(5)
            ForEach(Array(tags), id: \.self) { tag in
                Label(tag, systemImage: "tag")
                    .searchCompletion(tag)
            }
        }
    }
}

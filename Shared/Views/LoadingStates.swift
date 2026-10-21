import SwiftUI

/// Full-area loading state for the library surfaces, so an empty screen
/// during a slow first iCloud scan reads as "working", never as "no fics".
struct LibraryLoadingView: View {
    let text: String

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text(text)
                .textRole(.dek)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .leatherBackground()
    }
}

/// List footer shown while more of the library is still streaming in.
struct LibraryLoadingFooter: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Finding more fics…")
                .textRole(.meta)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

extension View {
    /// The system "No Results for …" state over a list whose search
    /// matched nothing — instead of a blank list.
    func noSearchResults(for query: String, when empty: Bool) -> some View {
        overlay {
            if empty, !query.isEmpty {
                NoResultsPage(query: query)
            }
        }
    }
}

/// Empty state for a Browse kind with nothing in it. While fic details are
/// still being read it says so; after that it says there's simply none.
struct BrowseEmptyView: View {
    let kind: TagKind
    @EnvironmentObject private var model: AppModel

    var body: some View {
        // Loading only until details first arrive — not on every periodic
        // rescan, which would flicker between this and the empty state.
        if !model.hasLoadedOnce || model.isMigrating || (model.isIndexing && model.detailsIndex.isEmpty) {
            LibraryLoadingView(text: "Reading fic details…")
        } else if model.library.isEmpty {
            EmptyPage(
                drawing: "EmptyBrowse",
                title: "Nothing to browse yet",
                message: "Fandoms, series and tags gather here once you've added fics.")
            .leatherBackground()
        } else {
            EmptyPage(
                title: "No \(kind.label.lowercased())",
                message: "None of your fics list any \(kind.label.lowercased()).")
            .leatherBackground()
        }
    }
}

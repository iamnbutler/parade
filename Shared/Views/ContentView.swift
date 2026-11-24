import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    #if os(iOS)
    /// The fic open to read. Presented here, at the root, not from the fic's
    /// page: the pager rebuilds its pages as the library refreshes, and a
    /// cover hung off one of them was dismissed along with it.
    @State private var reading: LibraryItem?
    @State private var tab = ContentView.initialTab
    #endif

    var body: some View {
        themedRoot
            .themedWindow()
    }

    @ViewBuilder
    private var themedRoot: some View {
        #if DEBUG
        if ThemeGallery.requested != nil {
            ThemeGallery()
                .palette(ThemeGallery.requested?.contains("noir") == true ? .noir : .leather)
        } else if let screen = ProcessInfo.processInfo.environment["PARADE_SCREEN"], screen.hasPrefix("search-form") {
            // For screenshots: the search form alone, as its sheet shows it,
            // scrolled to a section: "search-form@categories".
            SearchForm(scrolledTo: screen.components(separatedBy: "@").dropFirst().first)
                .onAppear { model.refreshLibrary() }
        } else if DebugScreen.standalone {
            DebugScreenView()
        } else {
            appRoot
        }
        #else
        appRoot
        #endif
    }

    private var appRoot: some View {
        root
            .overlay(alignment: .bottom) {
                if let toast = model.toast {
                    ToastView(text: toast)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: model.toast)
            .sheet(isPresented: Binding(
                get: { !model.contentChoiceMade },
                set: { if !$0 { model.finishContentChoice() } }
            )) {
                ContentChoiceView()
            }
    }

    @ViewBuilder
    private var root: some View {
        #if os(macOS)
        MacRootView()
            .frame(minWidth: 700, minHeight: 420)
        #else
        TabView(selection: $tab) {
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }
                .tag("library")
            ToReadView()
                .tabItem { Label("To Read", systemImage: "bookmark") }
                .tag("to-read")
            CollectionsView()
                .tabItem { Label("Collections", systemImage: "rectangle.stack.fill") }
                .tag("collections")
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag("search")
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag("settings")
        }
        .environment(\.readFic) { reading = $0 }
        .fullScreenCover(item: $reading) { item in
            NavigationStack {
                ReaderView(item: item)
                    .navigationTitle(item.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { reading = nil }
                        }
                    }
            }
            .themedWindow()
        }
        #endif
    }
}

#if os(iOS)
extension ContentView {
    static var initialTab: String {
        #if DEBUG
        DebugScreen.tab ?? "library"
        #else
        "library"
        #endif
    }
}
#endif

/// A short floating message, e.g. the result of updating one fic.
private struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(TextRole.dek.font)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .embossed(cornerRadius: 22, lifted: true)
            .padding(.horizontal, 24)
            #if os(iOS)
            .padding(.bottom, 96)  // clear the tab bar
            #else
            .padding(.bottom, 20)
            #endif
            .allowsHitTesting(false)
    }
}

import SwiftUI

/// Checkable collection list for one fic, plus "New Collection…" — the contents of a
/// Collections menu (row context menu, detail page button).
struct CollectionMenuItems: View {
    let item: LibraryItem
    @Binding var showNewCollection: Bool
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ForEach(model.collections.names, id: \.self) { name in
            Toggle(name, isOn: Binding(
                get: { model.isInCollection(item, name) },
                set: { _ in model.toggle(item, inCollection: name) }))
        }
        if !model.collections.names.isEmpty { Divider() }
        Button {
            showNewCollection = true
        } label: {
            Label("New Collection…", systemImage: "plus")
        }
    }
}

extension View {
    /// Asks for a collection name: `onSave` gets the text when confirmed.
    func collectionNameAlert(
        _ title: String,
        isPresented: Binding<Bool>,
        initial: String = "",
        message: String? = nil,
        action: String = "Create",
        isValid: @escaping (String) -> Bool,
        onSave: @escaping (String) -> Void
    ) -> some View {
        modifier(CollectionNameAlert(
            title: title, isPresented: isPresented, initial: initial,
            message: message, action: action, isValid: isValid, onSave: onSave))
    }

    /// "New Collection" prompt; the new collection gets `item` added, if given.
    func newCollectionAlert(isPresented: Binding<Bool>, adding item: LibraryItem? = nil, model: AppModel) -> some View {
        collectionNameAlert(
            "New collection", isPresented: isPresented,
            message: item.map { "“\($0.title)” goes in the new collection." }
                ?? "Collections are your own categories, separate from AO3's tags.",
            isValid: { model.collections.isAvailable($0) }
        ) { name in
            if let created = model.createCollection(name), let item {
                model.toggle(item, inCollection: created)
            }
        }
    }
}

private struct CollectionNameAlert: ViewModifier {
    let title: String
    @Binding var isPresented: Bool
    let initial: String
    let message: String?
    let action: String
    let isValid: (String) -> Bool
    let onSave: (String) -> Void

    func body(content: Content) -> some View {
        // A sheet drawn in the theme, not a system alert.
        content.sheet(isPresented: $isPresented) {
            CollectionNameSheet(
                title: title, initial: initial, message: message, action: action,
                isValid: isValid, onSave: onSave)
        }
    }
}

private struct CollectionNameSheet: View {
    let title: String
    let initial: String
    let message: String?
    let action: String
    let isValid: (String) -> Bool
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).textRole(.heading)
            if let message {
                Text(message)
                    .textRole(.subtitle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TextField("Collection name", text: $name)
                .textFieldStyle(.plain)
                .font(TextRole.body.font)
                .focused($focused)
                .onSubmit(save)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .debossed(cornerRadius: 10)
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.leather)
                    .keyboardShortcut(.cancelAction)
                Button(action, action: save)
                    .buttonStyle(.leatherProminent)
                    .keyboardShortcut(.defaultAction)
                    // Blank and taken names (any capitalization) can't be saved.
                    .disabled(!isValid(name))
            }
            .padding(.top, 4)
        }
        .padding(26)
        #if os(macOS)
        .frame(width: 420)
        #else
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.height(280)])
        #endif
        .leatherBackground()
        .themedWindow()
        .onAppear {
            name = initial
            focused = true
        }
    }

    private func save() {
        guard isValid(name) else { return }
        onSave(name)
        dismiss()
    }
}

#if os(iOS)
/// The Collections tab: the user's own categories.
struct CollectionsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showNewCollection = false
    @State private var pendingDelete: String?
    @State private var renaming: String?

    var body: some View {
        NavigationStack {
            Group {
                if model.collections.names.isEmpty {
                    EmptyPage(
                        drawing: "EmptyCollections",
                        title: "No collections yet",
                        message: "Collections are your own shelves, separate from AO3's tags. Make one, then long-press any fic to add it.")
                    {
                        Button { showNewCollection = true } label: { Label("New collection", systemImage: "plus") }
                    }
                    .leatherBackground()
                } else {
                    List {
                        ForEach(model.collections.names, id: \.self) { name in
                            NavigationLink(value: CollectionSelection(name: name)) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(name).textRole(.rowTitle).lineLimit(1)
                                    Spacer()
                                    Numeral(value: model.items(inCollection: name).count)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button { pendingDelete = name } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(SwipeTint.delete)
                                Button { renaming = name } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(SwipeTint.update)
                            }
                        }
                        .leatherRows()
                    }
                    .leatherList()
                    .refreshable { await model.refreshLibraryNow() }
                }
            }
            .navigationTitle("Collections")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showNewCollection = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New collection")
                }
            }
            .ficDestinations()
        }
        .newCollectionAlert(isPresented: $showNewCollection, model: model)
        .collectionNameAlert(
            "Rename collection",
            isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
            initial: renaming ?? "",
            action: "Rename",
            isValid: { model.collections.isAvailable($0, renaming: renaming) }
        ) { name in
            if let old = renaming { model.renameCollection(old, to: name.trimmingCharacters(in: .whitespaces)) }
        }
        // An alert, not a confirmation dialog: on iPhone the dialog
        // anchored itself to the whole screen.
        .alert(
            "Delete the collection “\(pendingDelete ?? "")”?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
        ) {
            Button("Delete Collection", role: .destructive) {
                if let name = pendingDelete { model.deleteCollection(name) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The fics in it stay in your library.")
        }
    }
}

/// The fics on one collection.
struct CollectionFicsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    /// State, not a let: renaming keeps this screen on the same collection.
    @State private var collection: String
    @State private var searchText = ""
    @State private var showRename = false
    @State private var confirmDelete = false

    init(collection: String) {
        _collection = State(initialValue: collection)
    }

    private var items: [LibraryItem] {
        model.items(inCollection: collection).filter { model.item($0, matches: searchText) }
    }

    var body: some View {
        Group {
            if model.items(inCollection: collection).isEmpty {
                EmptyPage(
                    title: "Nothing in this collection yet",
                    message: "Long-press a fic anywhere in Parade and choose Collections.")
                .leatherBackground()
            } else {
                List {
                    ForEach(items) { item in
                        NavigationLink(value: FicRoute(item: item, list: .collection(collection, query: searchText))) {
                            FicRow(item: item, showsAuthor: true, collection: collection)
                        }
                    }
                    .leatherRows()
                }
                .leatherList()
                .backToTop { items.first?.id }
                .noSearchResults(for: searchText, when: items.isEmpty)
                .ficSearch(text: $searchText, prompt: "Filter collection…")
                .refreshable { await model.refreshLibraryNow() }
            }
        }
        .navigationTitle(collection)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Rename…", systemImage: "pencil") { showRename = true }
                    Button("Delete Collection", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Collection options")
            }
        }
        .collectionNameAlert(
            "Rename collection", isPresented: $showRename, initial: collection, action: "Rename",
            isValid: { model.collections.isAvailable($0, renaming: collection) }
        ) { name in
            let clean = name.trimmingCharacters(in: .whitespaces)
            if model.renameCollection(collection, to: clean) { collection = clean }
        }
        .alert("Delete the collection “\(collection)”?", isPresented: $confirmDelete) {
            Button("Delete Collection", role: .destructive) {
                model.deleteCollection(collection)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The fics in it stay in your library.")
        }
    }
}
#endif

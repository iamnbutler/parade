import SwiftUI
import AO3Kit

struct AddFicSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var linkText = ""
    /// The log is shown only once a download starts here — older lines are
    /// some other action's business.
    @State private var startedHere = false
    /// Save into To Read rather than the library.
    @State private var toRead: Bool

    init(toRead: Bool = false) {
        _toRead = State(initialValue: toRead)
    }

    private var linkCount: Int { AO3Link.all(in: linkText).count }

    var body: some View {
        #if os(macOS)
        macSheet
            .interactiveDismissDisabled(model.isWorking)
        #else
        iosSheet
            .presentationDetents([.medium, .large])
            .interactiveDismissDisabled(model.isWorking)
        #endif
    }

    private var footnote: String {
        if linkCount > 1 { return "\(linkCount) links — they download one after another." }
        return toRead
            ? "Saved to To Read, a folder of its own beside the library. Add a fic to the library when you want to keep it."
            : "Works and whole series — paste one link or a whole batch. The EPUB is AO3's own export, filed as Author/Title in your library."
    }

    private var destinationPicker: some View {
        Picker("Save to", selection: $toRead) {
            Text("Library").tag(false)
            Text("To Read").tag(true)
        }
        .pickerStyle(.segmented)
        .disabled(model.isWorking)
    }

    private var activity: [String] {
        startedHere ? model.statusLines : []
    }

    private var downloadTitle: String {
        linkCount > 1 ? "Download \(linkCount)" : "Download"
    }

    #if os(macOS)
    /// The Mac sheet is drawn whole: a toolbar here would bring back the
    /// system title bar and button strip.
    private var macSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add fics").textRole(.heading)
            VStack(alignment: .leading, spacing: 8) {
                Text("Links from AO3").textRole(.kicker)
                destinationPicker
                    .labelsHidden()
                    .fixedSize()
                linkField
                    .textFieldStyle(.plain)
                    .font(TextRole.body.font)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .debossed(cornerRadius: 10)
                Text(footnote).textRole(.meta)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !activity.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Activity").textRole(.kicker)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(activity.enumerated()), id: \.offset) { _, line in
                                ActivityLine(line: line)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxHeight: 110)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.leather)
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isWorking)
                if model.isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 90)
                } else {
                    Button(downloadTitle, action: startDownload)
                        .buttonStyle(.leatherProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(linkCount == 0)
                }
            }
        }
        .padding(26)
        .frame(width: 480, height: 380)
        .leatherBackground()
    }
    #else
    private var iosSheet: some View {
        NavigationStack {
            Form {
                LeatherSection(title: "Links from AO3") {
                    destinationPicker
                    linkField
                } footer: {
                    Text(footnote)
                }

                if !activity.isEmpty {
                    LeatherSection("Activity") {
                        ForEach(Array(activity.enumerated()), id: \.offset) { _, line in
                            ActivityLine(line: line)
                        }
                    }
                }
            }
            .leatherForm()
            .navigationTitle("Add fics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(model.isWorking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.isWorking {
                        ProgressView()
                    } else {
                        Button(downloadTitle, action: startDownload)
                            .disabled(linkCount == 0)
                    }
                }
            }
        }
    }
    #endif

    private var linkField: some View {
        let field = TextField("Paste AO3 work or series links", text: $linkText, axis: .vertical)
            .lineLimit(3...8)
            .autocorrectionDisabled()
            .onSubmit(startDownload)
        #if os(iOS)
        return field
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
        #else
        return field
        #endif
    }

    private func startDownload() {
        let text = linkText
        guard !text.isEmpty, !model.isWorking else { return }
        startedHere = true
        Task {
            await model.handle(text, toRead: toRead)
            // Success closes the sheet; an error keeps it open to read.
            if model.statusLines.contains(where: { $0.hasPrefix("✓") }),
               !model.statusLines.contains(where: { $0.hasPrefix("⚠️") }) {
                dismiss()
            }
        }
    }
}

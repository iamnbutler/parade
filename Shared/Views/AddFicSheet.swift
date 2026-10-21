import SwiftUI
import AO3Kit

struct AddFicSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var linkText = ""
    /// The log is shown only once a download starts here — older lines are
    /// some other action's business.
    @State private var startedHere = false

    private var linkCount: Int { AO3Link.all(in: linkText).count }

    var body: some View {
        NavigationStack {
            Form {
                LeatherSection(title: "Links from AO3") {
                    linkField
                    PasteButton(payloadType: String.self) { strings in
                        guard let text = strings.first else { return }
                        Task { @MainActor in
                            linkText = text
                            startDownload()
                        }
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonBorderShape(.capsule)
                    .tint(palette.rose)
                } footer: {
                    if linkCount > 1 {
                        Text("\(linkCount) links — they download one after another.")
                    } else {
                        Text("Works and whole series — paste one link or a whole batch. The EPUB is AO3's own export, filed as Author/Title in your library.")
                    }
                }

                if startedHere, !model.statusLines.isEmpty {
                    LeatherSection("Activity") {
                        ForEach(Array(model.statusLines.enumerated()), id: \.offset) { _, line in
                            ActivityLine(line: line)
                        }
                    }
                }
            }
            .leatherForm()
            #if os(macOS)
            .formStyle(.grouped)
            .buttonStyle(.leather)
            #endif
            .navigationTitle("Add fics")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(model.isWorking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.isWorking {
                        ProgressView()
                            #if os(macOS)
                            .controlSize(.small)
                            #endif
                    } else {
                        Button(linkCount > 1 ? "Download \(linkCount)" : "Download", action: startDownload)
                            .disabled(linkCount == 0)
                    }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #else
        .frame(width: 440, height: 340)
        #endif
        .interactiveDismissDisabled(model.isWorking)
    }

    private var linkField: some View {
        let field = TextField("AO3 work or series links", text: $linkText, axis: .vertical)
            .lineLimit(1...8)
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
            await model.handle(text)
            // Success closes the sheet; an error keeps it open to read.
            if model.statusLines.contains(where: { $0.hasPrefix("✓") }),
               !model.statusLines.contains(where: { $0.hasPrefix("⚠️") }) {
                dismiss()
            }
        }
    }
}

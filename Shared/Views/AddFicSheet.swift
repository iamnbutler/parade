import SwiftUI

struct AddFicSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var linkText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
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
                } footer: {
                    Text("Works and whole series. The EPUB is AO3's own export, filed as Author/Title in your library.")
                }

                if !model.statusLines.isEmpty {
                    Section("Activity") {
                        ForEach(Array(model.statusLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.callout.monospaced())
                                .foregroundStyle(line.hasPrefix("⚠️") ? .red : .secondary)
                        }
                    }
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .navigationTitle("Add Fic")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.isWorking {
                        ProgressView()
                            #if os(macOS)
                            .controlSize(.small)
                            #endif
                    } else {
                        Button("Download", action: startDownload)
                            .disabled(linkText.isEmpty)
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
        let field = TextField("AO3 work or series link", text: $linkText, axis: .vertical)
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

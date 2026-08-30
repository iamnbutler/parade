#if os(macOS)
import SwiftUI

/// Compact popover for the always-running menu-bar presence. The full
/// library lives in the main window (Open Library).
struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var linkText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Paste an AO3 link…", text: $linkText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(startDownload)
                Button(action: startDownload) {
                    if model.isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                    }
                }
                .disabled(model.isWorking || linkText.isEmpty)
            }

            if !model.statusLines.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(model.statusLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption.monospaced())
                            .foregroundStyle(line.hasPrefix("⚠️") ? .red : .secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Divider()
            HStack {
                Button("Open Library") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Button("Scan Now") { model.scan() }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: 340)
    }

    private func startDownload() {
        let text = linkText
        guard !text.isEmpty else { return }
        Task {
            await model.handle(text)
            linkText = ""
        }
    }
}
#endif

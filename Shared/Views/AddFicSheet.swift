import SwiftUI
import AO3Kit

struct AddFicSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var linkText = ""
    /// The log is shown only once a download starts here — older lines are
    /// some other action's business.
    @State private var startedHere = false
    @State private var task: Task<Void, Never>?
    /// Save into To Read rather than the library.
    @State private var toRead: Bool

    init(toRead: Bool = false) {
        _toRead = State(initialValue: toRead)
    }

    private var linkCount: Int { AO3Link.all(in: linkText).count }
    private var isBlank: Bool { linkText.allSatisfy(\.isWhitespace) }
    /// Something is pasted but no link in it is one Parade knows. Download
    /// stays tappable then, and says so, rather than going quietly grey.
    private var unrecognized: Bool { !isBlank && linkCount == 0 }
    @Environment(\.palette) private var palette

    var body: some View {
        #if os(macOS)
        macSheet
            .interactiveDismissDisabled(model.isWorking && !model.inAO3Line)
        #else
        iosSheet
            .presentationDetents([.medium, .large])
            .interactiveDismissDisabled(model.isWorking && !model.inAO3Line)
        #endif
    }

    private var footnote: String {
        if linkCount == 0, !linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Parade doesn't see an AO3 link here yet. Paste a work or series link, like archiveofourown.org/works/12345."
        }
        if linkCount > 1 { return "\(linkCount) links — they download one after another." }
        if case .archivedWork? = AO3Link(text: linkText) {
            return "A Wayback Machine copy: Parade saves the work from the archived page, for when AO3 is down. "
                + "Snapshots with ?view_full_work=true have every chapter."
        }
        if case .ellipsus? = AO3Link(text: linkText) {
            return "An Ellipsus Reader link: Parade saves the story as an EPUB in an ellipsus folder. It has no AO3 link until you link it."
        }
        if case .ao3saver? = AO3Link(text: linkText) {
            return "An ao3saver.com copy: Parade saves the work from that saved version, no AO3 needed."
        }
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
                    .foregroundStyle(unrecognized ? palette.alert : palette.inkSoft)
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
                Button(model.inAO3Line ? "Stop waiting" : "Cancel") { cancel() }
                    .buttonStyle(.leather)
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isWorking && !model.inAO3Line)
                if model.isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 90)
                } else {
                    Button(downloadTitle, action: startDownload)
                        .buttonStyle(.leatherProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(isBlank)
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
                        .foregroundStyle(unrecognized ? palette.alert : palette.inkSoft)
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
                    Button(model.inAO3Line ? "Stop waiting" : "Cancel") { cancel() }
                        .disabled(model.isWorking && !model.inAO3Line)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.isWorking {
                        ProgressView()
                    } else {
                        Button(downloadTitle, action: startDownload)
                            .disabled(isBlank)
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

    /// Closes the sheet; while in AO3's waiting room, also gives up the wait.
    private func cancel() {
        if model.isWorking { task?.cancel() }
        dismiss()
    }

    private func startDownload() {
        let text = linkText
        guard !text.isEmpty, !model.isWorking else { return }
        startedHere = true
        task = Task {
            await model.handle(text, toRead: toRead)
            // Success closes the sheet; an error keeps it open to read.
            if model.statusLines.contains(where: { $0.hasPrefix("✓") }),
               !model.statusLines.contains(where: { $0.hasPrefix("⚠️") }) {
                dismiss()
            }
        }
    }
}

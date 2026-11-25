import SwiftUI

/// Where Parade points people for the things it doesn't do itself: its own
/// policy and support pages, and AO3's form for reporting a work. One place,
/// so the pages can move to another address without a hunt.
enum ParadeLinks {
    static let privacy = URL(string: "https://parade.iamnbutler.workers.dev/privacy/")!
    static let support = URL(string: "https://parade.iamnbutler.workers.dev/support/")!

    /// AO3's Policy & Abuse form, with the work's link filled in when AO3
    /// takes it from the address (otherwise it's pasted into the form).
    static func ao3Report(for work: URL? = nil) -> URL {
        var parts = URLComponents(string: "https://archiveofourown.org/abuse_reports/new")!
        if let work { parts.queryItems = [URLQueryItem(name: "url", value: work.absoluteString)] }
        return parts.url!
    }
}

/// The first-run question: may search show works AO3 rates Mature or
/// Explicit? Closing it without answering leaves them hidden.
struct ContentChoiceView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Text("Before you search")
                .textRole(.title)
                .multilineTextAlignment(.center)
            Text("Some works on AO3 are rated Mature or Explicit and contain adult themes.")
                .textRole(.body)
                .multilineTextAlignment(.center)
            Text("You can change this in Settings.")
                .textRole(.dek)
                .multilineTextAlignment(.center)
            VStack(spacing: 10) {
                Button {
                    model.setMatureContent(true)
                    dismiss()
                } label: {
                    Text("I'm 18 or older: show them").frame(maxWidth: .infinity)
                }
                .buttonStyle(.leatherProminent)
                Button {
                    model.setMatureContent(false)
                    dismiss()
                } label: {
                    Text("Keep them hidden").frame(maxWidth: .infinity)
                }
                .buttonStyle(.leather)
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: 420)
        .padding(.horizontal, 28)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .leatherBackground()
        .themedWindow()
        #if os(iOS)
        .presentationDetents([.medium])
        #else
        .frame(minWidth: 460, minHeight: 360)
        #endif
    }
}

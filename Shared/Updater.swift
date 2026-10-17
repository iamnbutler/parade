#if os(macOS)
import SwiftUI
import Sparkle

/// Sparkle auto-updates: checks the GitHub Releases appcast on a schedule
/// and on demand. Update archives are verified against the EdDSA public key
/// in Info.plist.
@MainActor
final class UpdaterModel: ObservableObject {
    // A test-library run never checks for (or installs) app updates.
    private let controller = SPUStandardUpdaterController(
        startingUpdater: AppModel.testLibrary == nil, updaterDelegate: nil, userDriverDelegate: nil)
    @Published var canCheck = false

    init() {
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheck)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
}

struct CheckForUpdatesButton: View {
    @ObservedObject var updater: UpdaterModel

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheck)
    }
}
#endif

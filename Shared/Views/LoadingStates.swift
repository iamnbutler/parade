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
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

/// List footer shown while more of the library is still streaming in.
struct LibraryLoadingFooter: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Finding more fics…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

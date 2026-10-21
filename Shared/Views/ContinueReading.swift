import SwiftUI

/// The fic read last, on any device, one tap from reading again — at the top
/// of the library, so opening the app and picking up where you left off is
/// the same motion.
struct ContinueReadingRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.readFic) private var readFic
    @Environment(\.palette) private var palette

    var body: some View {
        if let item = model.lastReadItem {
            Button {
                readFic?(item)
            } label: {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Continue reading").textRole(.kicker)
                        Text(item.title)
                            .textRole(.rowTitle)
                            .lineLimit(2)
                        Text(subtitle(item))
                            .textRole(.meta)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "book")
                        .font(.system(size: 18))
                        .foregroundStyle(palette.rose)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .embossed(cornerRadius: 12)
            }
            .buttonStyle(.plain)
            .disabled(!item.isDownloaded)
            .accessibilityLabel("Continue reading \(item.title)")
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            #if os(macOS)
            .listRowInsets(EdgeInsets(top: 2, leading: 20, bottom: 14, trailing: 20))
            #else
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 12, trailing: 16))
            #endif
        }
    }

    private func subtitle(_ item: LibraryItem) -> String {
        var parts = ["by \(item.author)"]
        if let date = model.lastReadDate {
            parts.append("read " + date.formatted(.relative(presentation: .named)))
        }
        return parts.joined(separator: " · ")
    }
}

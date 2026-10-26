import SwiftUI

/// The id a list gives its first row (on the Mac, its PageHeader) so Back
/// to Top has somewhere to scroll to.
enum ListTop {
    static let id = "list-top"
}

extension View {
    /// Once a long list is scrolled past its first screen, floats a Back to
    /// Top arrow in the bottom corner, with a Resume pill for the fic read
    /// last beside it. `top` names the list's first row; it's asked only on
    /// a tap. iOS 18 / macOS 15 and later — earlier systems go without.
    func backToTop(_ top: @escaping () -> AnyHashable? = { ListTop.id }) -> some View {
        modifier(BackToTop(top: top))
    }
}

private struct BackToTop: ViewModifier {
    let top: () -> AnyHashable?
    @State private var scrolledDown = false

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            tracked(content)
                .overlay(alignment: .bottomTrailing) {
                    if scrolledDown {
                        FloatingListControls {
                            guard let id = top() else { return }
                            withAnimation(.snappy) { proxy.scrollTo(id, anchor: .top) }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .bottomTrailing)))
                    }
                }
        }
    }

    @ViewBuilder
    private func tracked(_ content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            // Every scroll maps to one Bool, and the action runs only when
            // it flips — not a state write per frame.
            content.onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top > geo.containerSize.height
            } action: { _, past in
                withAnimation(.snappy(duration: 0.25)) { scrolledDown = past }
            }
        } else {
            content
        }
    }
}

/// The floating pair: "Resume <fic>" and an arrow back to the top.
private struct FloatingListControls: View {
    let toTop: () -> Void
    @EnvironmentObject private var model: AppModel
    @Environment(\.readFic) private var readFic
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            if let item = model.lastReadItem, item.isDownloaded, let readFic {
                Button { readFic(item) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("Resume")
                            .font(.reading(14, relativeTo: .footnote, italic: true))
                            .foregroundStyle(palette.gold)
                        // Shortened by hand: a width cap made the pill
                        // stretch to it even for a short title.
                        Text(Self.short(item.title))
                            .font(.reading(14, relativeTo: .footnote))
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .contentShape(Capsule())
                    .embossed(cornerRadius: 20, lifted: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Resume reading \(item.title)")
                .help("Resume reading \(item.title)")
            }
            Button(action: toTop) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.gold)
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
                    .embossed(cornerRadius: 20, lifted: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to top")
            .help("Back to top")
        }
        .padding(16)
    }

    private static func short(_ title: String) -> String {
        title.count <= 22 ? title : title.prefix(20).trimmingCharacters(in: .whitespaces) + "…"
    }
}

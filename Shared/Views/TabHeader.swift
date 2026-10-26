#if os(iOS)
import SwiftUI

extension View {
    /// A tab's first page with its own header in place of the system bar:
    /// an optional search field and add button, then the page title and an
    /// optional accessory (the Library's Order menu). The header slides
    /// away while the list scrolls down and comes back when it scrolls up,
    /// and stays while a search has text.
    func tabHeader<Accessory: View>(
        _ title: String,
        search: Binding<String>? = nil,
        prompt: String = "Search",
        onSubmitSearch: @escaping (String) -> Void = { _ in },
        add: (label: String, action: () -> Void)? = nil,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }
    ) -> some View {
        modifier(TabHeaderModifier(
            header: TabHeader(title: title, search: search, prompt: prompt,
                              onSubmitSearch: onSubmitSearch, add: add, accessory: accessory),
            pinned: !(search?.wrappedValue.isEmpty ?? true)))
    }
}

private struct TabHeaderModifier<Accessory: View>: ViewModifier {
    let header: TabHeader<Accessory>
    let pinned: Bool
    @State private var hidden = false
    /// The whole page's size, safe areas included — the size the page's
    /// own LeatherBackground is drawn at.
    @State private var page: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self) { proxy in
                CGSize(width: proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing,
                       height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom)
            } action: { page = $0 }
            .toolbar(.hidden, for: .navigationBar)
            .hidesOnScrollDown($hidden)
            .safeAreaInset(edge: .top, spacing: 0) {
                Group {
                    if hidden && !pinned {
                        // Just a backing for the status bar, so rows don't
                        // run under the clock bare.
                        Color.clear.frame(height: 0)
                    } else {
                        header
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity)
                .background { HeaderBand(page: page).ignoresSafeArea(edges: .top) }
            }
    }
}

/// The top of the page's own leather: the same background drawn at the
/// page's full size from the top of the screen, cut to the header — so the
/// light, vignette and grain run on without a seam. (The header sits in the
/// page's inset, not in a UIKit list header, where a slice like this washed
/// out rows mid-scroll.)
private struct HeaderBand: View {
    let page: CGSize

    var body: some View {
        Color.clear
            .overlay(alignment: .top) {
                LeatherBackground()
                    .frame(width: max(page.width, 1), height: max(page.height, 1))
            }
            .clipped()
            // Clipping hides the rest of the page-sized background but
            // doesn't stop it taking touches: it swallowed every scroll.
            .allowsHitTesting(false)
    }
}

private struct TabHeader<Accessory: View>: View {
    let title: String
    let search: Binding<String>?
    let prompt: String
    let onSubmitSearch: (String) -> Void
    let add: (label: String, action: () -> Void)?
    let accessory: () -> Accessory
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if search != nil || add != nil {
                HStack(spacing: 10) {
                    if let search {
                        HeaderSearchField(text: search, prompt: prompt, onSubmit: onSubmitSearch)
                    } else {
                        Spacer()
                    }
                    if let add {
                        Button(action: add.action) {
                            Image(systemName: "plus")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(palette.ink)
                                .frame(width: 40, height: 40)
                                .contentShape(Circle())
                                .embossed(cornerRadius: 20)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(add.label)
                    }
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .textRole(.pageTitle)
                    .lineLimit(1)
                Spacer()
                accessory()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }
}

private struct HeaderSearchField: View {
    @Binding var text: String
    let prompt: String
    let onSubmit: (String) -> Void
    @Environment(\.palette) private var palette
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(palette.inkSoft)
            TextField(prompt, text: $text)
                .font(TextRole.body.font)
                .foregroundStyle(palette.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($focused)
                .onSubmit { onSubmit(text) }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(palette.inkFaint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .debossed(cornerRadius: 20)
        .contentShape(Capsule())
        .onTapGesture { focused = true }
    }
}

// MARK: - hiding on scroll

extension View {
    /// Sets `hidden` while the list scrolls down, clears it when it scrolls
    /// up or reaches the top. iOS 18; earlier, `hidden` stays false.
    func hidesOnScrollDown(_ hidden: Binding<Bool>) -> some View {
        modifier(HidesOnScrollDown(hidden: hidden))
    }
}

private struct HidesOnScrollDown: ViewModifier {
    @Binding var hidden: Bool
    /// Per-frame bookkeeping in a plain object: changing it doesn't redraw.
    @State private var track = ScrollTrack()

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                // The action sees every offset, but state changes only when
                // the direction flips — not a write per frame.
                .onScrollGeometryChange(for: ScrollSample.self) { geo in
                    ScrollSample(y: geo.contentOffset.y, inset: geo.contentInsets.top)
                } action: { old, new in
                    guard let hide = track.decide(old: old, new: new, now: Date()), hide != hidden else { return }
                    track.flipped(at: Date())
                    withAnimation(.easeInOut(duration: 0.22)) { hidden = hide }
                }
        } else {
            content
        }
    }
}

private struct ScrollSample: Equatable {
    var y: CGFloat
    var inset: CGFloat
}

/// Decides hide/show from scrolling — only from the reader's own scrolling.
/// Showing or hiding a bar changes the list's insets and offset, which
/// looks like a scroll the other way; reacting to that flipped the bar back
/// and forth forever. So: frames where the inset moved are ignored, nothing
/// is decided while the bar is still sliding, and a direction has to hold
/// for a short distance before it counts.
private final class ScrollTrack {
    private var travel: CGFloat = 0
    private var settledAt = Date.distantPast

    func decide(old: ScrollSample, new: ScrollSample, now: Date) -> Bool? {
        guard old.inset == new.inset, now >= settledAt else {
            travel = 0
            return nil
        }
        if new.y + new.inset < 60 { return false }  // at the top: always shown
        let delta = new.y - old.y
        travel = (delta > 0) == (travel > 0) ? travel + delta : delta
        if travel > 24 { return true }
        if travel < -24 { return false }
        return nil
    }

    func flipped(at now: Date) {
        travel = 0
        settledAt = now.addingTimeInterval(0.35)
    }
}
#endif

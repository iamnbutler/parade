import SwiftUI

// Texture and depth — docs/design-system.md §3 and §6.

/// The page: leather lit warmly from the top left, a vignette at the
/// bottom, and fine grain. It stays fixed behind scrolling content.
struct LeatherBackground: View {
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            palette.leather
            EllipticalGradient(
                colors: [Color(hex: 0xFFE1CD, opacity: 0.045), .clear],
                center: UnitPoint(x: 0.3, y: 0), startRadiusFraction: 0, endRadiusFraction: 0.6)
            EllipticalGradient(
                colors: [.black.opacity(palette.vignette), .clear],
                center: UnitPoint(x: 0.5, y: 1.2), startRadiusFraction: 0, endRadiusFraction: 0.7)
            if palette.silk {
                // Noir: two soft diagonal bands of sheen and an oxblood glow.
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.2),
                        .init(color: .white.opacity(0.03), location: 0.32),
                        .init(color: .clear, location: 0.44),
                        .init(color: .white.opacity(0.025), location: 0.62),
                        .init(color: .clear, location: 0.74),
                    ],
                    startPoint: UnitPoint(x: 0, y: 0.1), endPoint: UnitPoint(x: 1, y: 0.9))
                EllipticalGradient(
                    colors: [Color(hex: 0xA01E32, opacity: 0.18), .clear],
                    center: UnitPoint(x: 0.9, y: 0), startRadiusFraction: 0, endRadiusFraction: 0.55)
            }
            Image(decorative: Grain.tile, scale: 2)
                .resizable(resizingMode: .tile)
                .opacity(palette.grain)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// The part of a larger `LeatherBackground` (at `backdrop`, in global
/// coordinates) that lies under this view — so a floating panel continues
/// the window's gradient instead of starting its own.
struct BackdropSlice: View {
    let backdrop: CGRect

    var body: some View {
        GeometryReader { geo in
            let here = geo.frame(in: .global)
            LeatherBackground()
                .frame(width: max(backdrop.width, here.width), height: max(backdrop.height, here.height))
                .offset(x: backdrop.minX - here.minX, y: backdrop.minY - here.minY)
        }
        .clipped()
    }
}

private struct LeatherPage: ViewModifier {
    @Environment(\.leatherBackdrop) private var backdrop
    @State private var frame: CGRect?

    func body(content: Content) -> some View {
        if backdrop {
            content
        } else {
            content
                .environment(\.backdropFrame, frame)
                .background {
                    LeatherBackground()
                        .background {
                            // Where the page sits, so pinned headers can
                            // show the same leather (WashBehind).
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear { frame = geo.frame(in: .global) }
                                    .onChange(of: geo.frame(in: .global)) { _, new in frame = new }
                            }
                            .ignoresSafeArea()
                        }
                }
        }
    }
}

private struct BackdropFrameKey: EnvironmentKey {
    static let defaultValue: CGRect? = nil
}

extension EnvironmentValues {
    /// The page's `LeatherBackground`, in global coordinates, once laid out.
    var backdropFrame: CGRect? {
        get { self[BackdropFrameKey.self] }
        set { self[BackdropFrameKey.self] = newValue }
    }
}

extension View {
    /// Pinned headers sit on the page's own leather, fading out below, so
    /// rows scrolling under them disappear instead of showing through.
    func washBehind() -> some View {
        modifier(WashBehind())
    }
}

private struct WashBehind: ViewModifier {
    @Environment(\.backdropFrame) private var backdrop
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        #if os(macOS)
        content.background {
            if let backdrop {
                BackdropSlice(backdrop: backdrop)
                    .mask {
                        LinearGradient(
                            stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.72),
                                    .init(color: .clear, location: 1)],
                            startPoint: .top, endPoint: .bottom)
                    }
                    // Out to the list's edges, and a little below for the fade.
                    .padding(.horizontal, -40)
                    .padding(.top, -6)
                    .padding(.bottom, -12)
                    .allowsHitTesting(false)
            }
        }
        #else
        // Only local pieces here — the page's color and grain. A slice of
        // the whole page, placed from global geometry, washed out the rows
        // while a UIKit list scrolled, overhang or not.
        content.background {
            ZStack {
                palette.leather
                Image(decorative: Grain.tile, scale: 2)
                    .resizable(resizingMode: .tile)
                    .opacity(palette.grain)
            }
            .padding(.horizontal, -40)
            .allowsHitTesting(false)
        }
        #endif
    }
}

private struct LeatherBackdropKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Set where one `LeatherBackground` already spans the area.
    var leatherBackdrop: Bool {
        get { self[LeatherBackdropKey.self] }
        set { self[LeatherBackdropKey.self] = newValue }
    }
}

/// A tile of fine film grain, baked once. The web version blends fractal
/// noise in overlay mode; on leather that mostly darkens, so the tile is
/// faint dark and light specks blended normally — no per-frame blending.
enum Grain {
    static let tile: CGImage = {
        let side = 192
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> Double {
            // SplitMix64: same grain every launch.
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return Double(z ^ (z >> 31)) / Double(UInt64.max)
        }
        for i in 0..<(side * side) {
            let n = (next() + next()) - 1  // -1...1, peaked at 0
            let light = n > 0
            let alpha = light ? n * 0.05 : -n * 0.11
            let value = light ? alpha : 0  // premultiplied white or black
            let byte = UInt8(max(0, min(255, value * 255)))
            pixels[i * 4] = byte
            pixels[i * 4 + 1] = byte
            pixels[i * 4 + 2] = byte
            pixels[i * 4 + 3] = UInt8(max(0, min(255, alpha * 255)))
        }
        let context = CGContext(
            data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }()
}

extension View {
    /// The leather page behind a screen — unless an ancestor already draws
    /// one leather backdrop for several columns (the Mac window), where a
    /// page of its own would restart the gradient at each column edge.
    func leatherBackground() -> some View {
        modifier(LeatherPage())
    }

    /// Raised: cards, the active nav row, primary doors. A top-lit gradient
    /// with an inner highlight above and a shadow line below.
    func embossed(cornerRadius: CGFloat = 14, lifted: Bool = false) -> some View {
        modifier(Embossed(cornerRadius: cornerRadius, lifted: lifted))
    }

    /// Pressed in: callouts, figure frames, tags and chips.
    func debossed(cornerRadius: CGFloat = 12) -> some View {
        modifier(Debossed(cornerRadius: cornerRadius))
    }
}

private struct Embossed: ViewModifier {
    let cornerRadius: CGFloat
    let lifted: Bool
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content.background {
            shape
                .fill(LinearGradient(colors: [palette.raised2, palette.raised],
                                     startPoint: .top, endPoint: .bottom))
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color(hex: 0xFFF0E1, opacity: 0.07), location: 0),
                                .init(color: .clear, location: 0.12),
                                .init(color: .clear, location: 0.88),
                                .init(color: .black.opacity(0.35), location: 1),
                            ],
                            startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
                .shadow(color: .black.opacity(lifted ? 0.28 : 0), radius: lifted ? 15 : 0, y: lifted ? 10 : 0)
        }
    }
}

private struct Debossed: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content.background {
            shape
                .fill(Color.black.opacity(0.2).shadow(.inner(color: .black.opacity(0.5), radius: 2, y: 1)))
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.85),
                                .init(color: Color(hex: 0xFFF0E1, opacity: 0.05), location: 1),
                            ],
                            startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
                }
        }
    }
}

/// The signature object: a raised card with a gold stitch 7pt in from the
/// edge, like a leather tag. One per page.
struct StitchedCard<Content: View>: View {
    var label: String?
    @ViewBuilder var content: Content
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label {
                Text(label).textRole(.kicker)
            }
            content
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .embossed(cornerRadius: 14, lifted: true)
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(
                    palette.goldFaint,
                    style: StrokeStyle(lineWidth: 1, dash: palette.solidStitch ? [] : [4, 3]))
                .padding(7)
                .allowsHitTesting(false)
        }
    }
}

/// A strip of translucent tape, as on a taped card or clipping.
struct Tape: View {
    var color: Color? = nil
    var width: CGFloat = 64
    var angle: Double = -4
    @Environment(\.palette) private var palette

    var body: some View {
        Rectangle()
            .fill(color ?? palette.gold.opacity(0.42))
            .frame(width: width, height: 18)
            .rotationEffect(.degrees(angle))
            .accessibilityHidden(true)
    }
}

/// Content on a raised card, tilted a little, taped across the top.
struct TapedCard<Content: View>: View {
    var tilt: Double = -1.6
    var tape: Color? = nil
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .padding(18)
            .embossed(cornerRadius: 6, lifted: true)
            .overlay(alignment: .top) { Tape(color: tape).offset(y: -9) }
            .rotationEffect(.degrees(reduceMotion ? 0 : tilt))
    }
}

/// Cream paper with dark ink, tilted, tape at one corner: "Begin with"
/// lists, notes, letters. Inside, the palette is Paper — except in Noir,
/// where it becomes a dark card with a gold inner hairline.
struct PaperClipping<Content: View>: View {
    var tilt: Double = -0.8
    @ViewBuilder var content: Content
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if palette.silk {
                content
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .embossed(cornerRadius: 4, lifted: true)
                    .overlay {
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(palette.goldFaint, lineWidth: 1)
                            .padding(6)
                            .allowsHitTesting(false)
                    }
            } else {
                content
                    .palette(.paper)
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(colors: [Color(hex: 0xEFE4D3), Color(hex: 0xE3D4BF)],
                                       startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 2))
                    .shadow(color: .black.opacity(0.4), radius: 18, x: 2, y: 14)
            }
        }
        .overlay(alignment: .topLeading) {
            Tape(color: palette.rose.opacity(0.4), width: 56, angle: -3)
                .offset(x: 24, y: -9)
        }
        .rotationEffect(.degrees(reduceMotion ? 0 : tilt))
    }
}

/// A divider in the rule color, one pixel thick.
struct Hairline: View {
    var gold = false
    @Environment(\.palette) private var palette
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(gold ? palette.goldFaint : palette.rule)
            .frame(height: 1 / displayScale)
            .accessibilityHidden(true)
    }
}

/// The centered gold ❦ that separates sections.
struct Fleuron: View {
    @Environment(\.palette) private var palette

    var body: some View {
        // Cormorant's own ❦ is a stub; Zapf Dingbats has the classic leaf.
        Text("❦")
            .font(.custom("ZapfDingbatsITC", size: 18, relativeTo: .title3))
            .foregroundStyle(palette.gold)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

/// A chip pressed into the leather: tags, small toggles.
struct Chip: View {
    let text: String
    var selected = false
    @Environment(\.palette) private var palette

    var body: some View {
        Text(text)
            .font(.reading(14, relativeTo: .footnote))
            .foregroundStyle(selected ? palette.rose : palette.inkSoft)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .debossed(cornerRadius: 8)
    }
}

/// Small embossed buttons in place of bordered pills. `prominent` puts the
/// label in rose — for the one action a page wants you to notice.
struct LeatherButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.reading(15, relativeTo: .subheadline, italic: prominent))
            .foregroundStyle(prominent ? palette.rose : palette.ink)
            .labelStyle(LeatherLabelStyle())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                if configuration.isPressed {
                    Color.clear.debossed(cornerRadius: 10)
                } else {
                    Color.clear.embossed(cornerRadius: 10)
                }
            }
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

/// Icon and title close together, the icon a touch smaller and softer.
struct LeatherLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .font(.system(size: 12, weight: .regular))
                .imageScale(.small)
                .opacity(0.8)
            configuration.title
        }
    }
}

extension ButtonStyle where Self == LeatherButtonStyle {
    static var leather: LeatherButtonStyle { LeatherButtonStyle() }
    static var leatherProminent: LeatherButtonStyle { LeatherButtonStyle(prominent: true) }
}

import SwiftUI

/// "Leather & Ink" colors — docs/design-system.md §2. One dark theme; Noir is
/// the richer variant used for Favorites; Paper is the cream clipping.
///
/// Rose is for interaction and emphasis, gold for ornament and structure.
struct Palette: Equatable {
    var leather: Color
    var leatherDeep: Color
    var raised: Color
    var raised2: Color
    var ink: Color
    var inkSoft: Color
    var inkFaint: Color
    /// A shade brighter than ink, for bold runs in reading text.
    var strong: Color
    var rose: Color
    var roseSoft: Color
    var gold: Color
    var goldFaint: Color
    var rule: Color
    var alert: Color
    /// Noir: a solid gold stitch on the stitched card instead of a dashed one.
    var solidStitch = false
    /// Noir: silk sheen and an oxblood glow on the background.
    var silk = false
    var grain: Double = 1

    static let leather = Palette(
        leather: Color(hex: 0x241B1E),
        leatherDeep: Color(hex: 0x1B1416),
        raised: Color(hex: 0x2D2226),
        raised2: Color(hex: 0x34282C),
        ink: Color(hex: 0xEFE3D3),
        inkSoft: Color(hex: 0xB9A89A),
        inkFaint: Color(hex: 0x8A7A70),
        strong: Color(hex: 0xF7ECDF),
        rose: Color(hex: 0xD8A39B),
        roseSoft: Color(hex: 0xD8A39B, opacity: 0.14),
        gold: Color(hex: 0xC8A46A),
        goldFaint: Color(hex: 0xC8A46A, opacity: 0.35),
        rule: Color(hex: 0xEFE3D3, opacity: 0.12),
        alert: Color(hex: 0xE8978F))

    static let noir = Palette(
        leather: Color(hex: 0x0E0B0C),
        leatherDeep: Color(hex: 0x060505),
        raised: Color(hex: 0x19131A),
        raised2: Color(hex: 0x211921),
        ink: Color(hex: 0xF4EADC),
        inkSoft: Color(hex: 0xC2B09D),
        inkFaint: Color(hex: 0x8A7967),
        strong: Color(hex: 0xFBF3E8),
        rose: Color(hex: 0xD77A84),
        roseSoft: Color(hex: 0xA01E32, opacity: 0.22),
        gold: Color(hex: 0xDCB872),
        goldFaint: Color(hex: 0xDCB872, opacity: 0.42),
        rule: Color(hex: 0xDCB872, opacity: 0.14),
        alert: Color(hex: 0xE8978F),
        solidStitch: true,
        silk: true,
        grain: 0.65)

    /// Dark ink on the cream paper clipping (§6 "Paper clipping").
    static let paper = Palette(
        leather: Color(hex: 0xEFE4D3),
        leatherDeep: Color(hex: 0xE3D4BF),
        raised: Color(hex: 0xE3D4BF),
        raised2: Color(hex: 0xEFE4D3),
        ink: Color(hex: 0x2E211F),
        inkSoft: Color(hex: 0x5C4840),
        inkFaint: Color(hex: 0x7F6B5E),
        strong: Color(hex: 0x1F1513),
        rose: Color(hex: 0x8B3A46),
        roseSoft: Color(hex: 0x8B3A46, opacity: 0.12),
        gold: Color(hex: 0x8B5A2B),
        goldFaint: Color(hex: 0x8B5A2B, opacity: 0.35),
        rule: Color(hex: 0x2E211F, opacity: 0.14),
        alert: Color(hex: 0xA2453C))
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.leather
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

extension View {
    /// Switches a subtree to another palette, with its ink and tint.
    func palette(_ palette: Palette) -> some View {
        environment(\.palette, palette)
            .foregroundStyle(palette.ink)
            .tint(palette.rose)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity)
    }
}

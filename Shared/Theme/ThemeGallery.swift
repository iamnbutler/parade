#if DEBUG
import SwiftUI

/// Every theme piece on one page, for tuning against the design doc.
/// Launch with PARADE_THEME_GALLERY=1 (and =noir for the Noir palette).
struct ThemeGallery: View {
    static var requested: String? { ProcessInfo.processInfo.environment["PARADE_THEME_GALLERY"] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Library, 3 of 26").textRole(.runningHead)
                    Text("The Long Way Home").textRole(.title)
                    Text("by inkandlamplight").textRole(.dek)
                }

                StitchedCard(label: "The summary") {
                    Text("Twelve years after the war, **Remus** keeps a bookshop by the sea. A letter arrives in a hand he hasn't seen since he was nineteen.")
                        .textRole(.body)
                }

                HStack(spacing: 8) {
                    Button {} label: { Label("Update", systemImage: "arrow.down.circle") }
                        .buttonStyle(.leatherProminent)
                    Button {} label: { Label("Share", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.leather)
                    Button {} label: { Label("Favorite", systemImage: "star") }
                        .buttonStyle(.leather)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Filed under").textRole(.kicker)
                    FlowLayout(spacing: 6) {
                        ForEach(["Slow burn", "Hurt/Comfort", "Epistolary", "Seaside"], id: \.self) {
                            Chip(text: $0)
                        }
                    }
                }

                Hairline()

                VStack(alignment: .leading, spacing: 0) {
                    Text("Ursula K. Le Guin").textRole(.kicker).padding(.bottom, 6)
                    ForEach(["A Wizard of Earthsea", "The Tombs of Atuan"], id: \.self) { title in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title).textRole(.rowTitle)
                            Text("Saved Oct 12 · 48,210 words").textRole(.meta)
                        }
                        .padding(.vertical, 10)
                        Hairline()
                    }
                }

                HStack {
                    Text("Before you start").font(.reading(17))
                    Spacer()
                    Numeral(value: 23)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .embossed(cornerRadius: 10)

                Text("A debossed callout: the waiting is real and it's hard. Every item here still counts.")
                    .textRole(.body)
                    .padding(18)
                    .debossed()

                HStack(alignment: .top, spacing: 24) {
                    TapedCard {
                        Image(systemName: "book.closed")
                            .font(.system(size: 44, weight: .ultraLight))
                            .frame(width: 110, height: 90)
                    }
                    PaperClipping {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Begin with").textRole(.kicker)
                            Text("Cues, not rules").textRole(.rowTitle)
                            Text("Where the habits come from.").textRole(.meta)
                        }
                    }
                }
                .padding(.top, 10)

                Fleuron()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 32)
        }
        .defaultScrollAnchor(Self.requested?.contains("bottom") == true ? .bottom : .top)
        .leatherBackground()
    }
}
#endif

// Equalizer page: preset tiles.

import AirBudsKit
import SwiftUI

struct EqualizerView: View {
    @EnvironmentObject var device: EarbudsController

    private var eq: EqState { device.state.eq }

    var body: some View {
        VStack(spacing: 8) {
            SubpageHeader(title: "Equalizer")

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(device.state.capabilities.eqPresets) { preset in
                    let selected = eq.preset == preset.id
                    Tile(symbol: Self.symbol(for: preset.key), name: preset.label,
                         detail: selected ? "Selected" : " ",
                         on: selected, pending: selected && eq.pending) {
                        device.setEqPreset(preset.id)
                    }
                    .disabled(eq.pending && !selected)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    static func symbol(for key: String) -> String {
        switch key {
        case "balanced": return "equal.circle"
        case "rock": return "guitars.fill"
        case "pop": return "music.note"
        case "classical": return "pianokeys"
        case "jazz": return "music.quarternote.3"
        case "country": return "music.note.house"
        default: return "music.note"
        }
    }
}

// Equalizer page: preset tiles, plus Custom with a slider per band when the
// earbuds have a Custom slot.

import AirBudsKit
import SwiftUI

struct EqualizerView: View {
    @EnvironmentObject var device: EarbudsController

    private var eq: EqState { device.state.eq }

    var body: some View {
        let customAvailable = !device.state.capabilities.eqBands.isEmpty
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
                if customAvailable {
                    let selected = eq.preset == CustomEq.id
                    Tile(symbol: "slider.vertical.3", name: "Custom",
                         detail: selected ? "Selected" : " ",
                         on: selected, pending: selected && eq.pending) {
                        device.selectCustomEq()
                    }
                    .disabled(eq.pending && !selected)
                }
            }
            .padding(.horizontal, 12)

            if customAvailable && eq.preset == CustomEq.id {
                CustomEqEditor()
                    .padding(.horizontal, 12)
                    .padding(.top, 2)
            }
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

// MARK: - Custom EQ

private struct CustomEqEditor: View {
    @EnvironmentObject var device: EarbudsController

    var body: some View {
        let bands = device.state.capabilities.eqBands
        let gains = device.state.eq.customGains
        VStack(spacing: 6) {
            HStack {
                Text("Custom EQ").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button("Reset") { device.resetCustomEq() }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                    .disabled(gains.allSatisfy { $0 == 0 })
            }
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(bands.enumerated()), id: \.offset) { index, hertz in
                    let gain: Int = index < gains.count ? gains[index] : 0
                    VStack(spacing: 3) {
                        Text(gain > 0 ? "+\(gain)" : "\(gain)")
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(gain == 0 ? Color.secondary : Color.primary)
                        GainSlider(value: gain) { device.setCustomGain(band: index, to: $0) }
                            .frame(height: 96)
                            .accessibilityLabel("\(CustomEq.label(hertz: hertz)) hertz")
                        Text(CustomEq.label(hertz: hertz))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text("Drag a band up or down; ±8 dB. AirBuds keeps these and sends them whenever Custom is on.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
    }
}

/// A vertical slider for one band's gain, in whole dB.
private struct GainSlider: View {
    let value: Int
    let onChange: (Int) -> Void

    private static let range = CustomEq.range
    private static let thumb: CGFloat = 12

    /// The thumb's centre for `gain`: +8 dB at the top, -8 dB at the bottom.
    private static func y(for gain: Int, usable: CGFloat) -> CGFloat {
        let span: CGFloat = CGFloat(range.upperBound - range.lowerBound)
        let fraction: CGFloat = CGFloat(gain - range.lowerBound) / span
        return thumb / 2 + (1 - fraction) * usable
    }

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let midX = geo.size.width / 2
            let span: CGFloat = CGFloat(Self.range.upperBound - Self.range.lowerBound)
            let usable: CGFloat = height - Self.thumb
            let zeroY: CGFloat = Self.y(for: 0, usable: usable)
            let valueY: CGFloat = Self.y(for: value, usable: usable)
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 4, height: usable)
                    .position(x: midX, y: height / 2)
                // Filled from 0 dB to the value.
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 4, height: abs(valueY - zeroY))
                    .position(x: midX, y: (valueY + zeroY) / 2)
                Rectangle()
                    .fill(Color.primary.opacity(0.3))
                    .frame(width: 10, height: 1)
                    .position(x: midX, y: zeroY)
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                    .frame(width: Self.thumb, height: Self.thumb)
                    .position(x: midX, y: valueY)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let offset: CGFloat = drag.location.y - Self.thumb / 2
                let fraction: CGFloat = 1 - offset / max(usable, 1)
                let raw: CGFloat = CGFloat(Self.range.lowerBound) + fraction * span
                let gain: Int = min(max(Int(raw.rounded()), Self.range.lowerBound), Self.range.upperBound)
                if gain != value { onChange(gain) }
            })
        }
        .accessibilityElement()
        .accessibilityValue("\(value) decibels")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(min(value + 1, Self.range.upperBound))
            case .decrement: onChange(max(value - 1, Self.range.lowerBound))
            @unknown default: break
            }
        }
    }
}

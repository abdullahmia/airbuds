// Main page: header, battery, volume and noise control; paired earbuds to
// connect when none are connected.

import AirBudsKit
import SwiftUI

struct MainView: View {
    @EnvironmentObject var device: EarbudsController
    @EnvironmentObject var nav: PanelNavigation
    @EnvironmentObject var volume: EarbudsVolume

    private var state: DeviceState { device.state }

    var body: some View {
        VStack(spacing: 0) {
            header
            if state.connected {
                Button { nav.page = .battery } label: { BatteryRow() }
                    .buttonStyle(HoverRowStyle())
                    .help("Battery Details")
                TimeLeft()
                if volume.level != nil {
                    PanelDivider()
                    VolumeSection()
                }
                if state.capabilities.noiseControl {
                    PanelDivider()
                    NoiseControlSection()
                }
            } else {
                DisconnectedSection()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(state.connected ? Color.accentColor : Color.primary.opacity(0.1))
                Image(nsImage: MenuBarIcon.make())
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(state.connected ? Color.white : Color.primary)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(state.connected ? (state.name ?? "Earbuds") : "No Earbuds")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(state.connected ? "Connected" : "Not connected")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HeaderButton(symbol: "slider.vertical.3", help: "Equalizer") { nav.page = .equalizer }
                .disabled(!state.connected || state.capabilities.eqPresets.isEmpty)
            HeaderButton(symbol: "gearshape", help: "Quick Settings") { nav.page = .quickSettings }
                .disabled(!state.connected)
            HeaderButton(symbol: "antenna.radiowaves.left.and.right.slash", help: "Disconnect") { device.disconnect() }
                .disabled(!state.connected)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

private struct HeaderButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @StateObject private var hovering = Local(false)
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.primary.opacity(hovering.value && enabled ? 0.1 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.35)
        .help(help)
        .onHover { hovering.value = $0 }
    }
}

// MARK: - Not connected

private struct DisconnectedSection: View {
    @EnvironmentObject var device: EarbudsController

    var body: some View {
        VStack(spacing: 0) {
            if device.paired.isEmpty {
                Text("Pair your Hoco earbuds in Bluetooth settings.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
            } else {
                SectionTitle("Your Earbuds")
                ForEach(device.paired) { earbuds in
                    PairedRow(earbuds: earbuds)
                }
                PanelDivider()
            }
            Button("Open Bluetooth Settings…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
            .font(.system(size: 12))
            .padding(.bottom, 10)
        }
    }
}

private struct PairedRow: View {
    let earbuds: PairedEarbuds
    @EnvironmentObject var device: EarbudsController

    var body: some View {
        // Connected for audio but the control link isn't up yet: that's connecting too.
        let busy: Bool = device.connecting == earbuds.address || earbuds.connected
        let failed: Bool = device.connectFailed == earbuds.address
        Button { device.connect(earbuds.address) } label: {
            HStack(spacing: 10) {
                IconBadge(symbol: "earbuds", pending: busy)
                VStack(alignment: .leading, spacing: 1) {
                    Text(earbuds.name).font(.system(size: 13)).lineLimit(1)
                    Text(busy ? "Connecting…" : failed ? "Couldn't connect. Are they out of the case?" : "Not connected")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if !busy {
                    Text("Connect").font(.system(size: 12)).foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(HoverRowStyle())
        .disabled(busy || device.connecting != nil)
        .help(busy ? "Connecting to \(earbuds.name)" : "Connect \(earbuds.name) to this Mac")
    }
}

// MARK: - Battery

private struct BatteryRow: View {
    @EnvironmentObject var device: EarbudsController

    var body: some View {
        let battery = device.state.battery
        HStack(spacing: 0) {
            BudColumn(symbol: "airpodpro.left", label: "Left", info: battery.left)
            BudColumn(symbol: "airpodpro.right", label: "Right", info: battery.right)
            // No case data (e.g. closed or out of range): drop the column so the buds sit centred.
            if let info = battery.case {
                BudColumn(symbol: "earbuds.case.fill", label: "Case", info: info)
            }
        }
        .padding(.vertical, 2)
    }
}

/// "About 3h 10m left" for the bud that runs out first, once there's an estimate.
private struct TimeLeft: View {
    @EnvironmentObject var device: EarbudsController
    @EnvironmentObject var store: BatteryHistoryStore

    var body: some View {
        // Re-read on every battery poll: `device` publishes each report.
        let _ = device.state.battery
        if let left = store.soonestEmpty() {
            Text(Duration.left(left))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
        }
    }
}

private struct BudColumn: View {
    let symbol: String
    let label: String
    let info: BatteryLevel?

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .frame(height: 34)
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                if info?.charging == true {
                    Image(systemName: "bolt.fill").font(.system(size: 8)).foregroundStyle(.green)
                }
                Text(info.map { "\($0.level)%" } ?? "—")
                    .font(.system(size: 11).monospacedDigit())
                BatteryGlyph(info: info)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .opacity(info == nil ? 0.4 : 1)
    }
}

private struct BatteryGlyph: View {
    let info: BatteryLevel?

    var body: some View {
        let level = CGFloat(info?.level ?? 0) / 100
        let low = (info.map { !$0.charging && $0.level <= 20 }) ?? false
        let color: Color = info?.charging == true ? .green : low ? .red : .primary
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.5)
                    .strokeBorder(Color.primary.opacity(0.35), lineWidth: 1)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: max(0, 18 * level))
                    .padding(1.5)
            }
            .frame(width: 22, height: 10)
            RoundedRectangle(cornerRadius: 1).fill(Color.primary.opacity(0.35)).frame(width: 1.5, height: 4)
        }
    }
}

// MARK: - Volume

private struct VolumeSection: View {
    @EnvironmentObject var volume: EarbudsVolume

    var body: some View {
        let level: Double = volume.level ?? 0
        VStack(spacing: 0) {
            SectionTitle("Volume")
            HStack(spacing: 10) {
                Button { volume.setMuted(!volume.muted) } label: {
                    IconBadge(symbol: AudioOutput.symbol(level: level, muted: volume.muted))
                }
                .buttonStyle(.plain)
                .help(volume.muted ? "Unmute" : "Mute")
                Slider(value: Binding(get: { level }, set: { volume.setLevel($0) }), in: 0...1)
                    .controlSize(.small)
                    .opacity(volume.muted ? 0.5 : 1)
                Text("\(Int((level * 100).rounded()))%")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 3)
        }
    }
}

// MARK: - Noise control

private struct NoiseControlSection: View {
    @EnvironmentObject var device: EarbudsController

    var body: some View {
        let caps = device.state.capabilities
        VStack(spacing: 0) {
            SectionTitle("Noise Control")
            option(.anc)
            option(.off)
            if caps.transparency {
                option(.transparency)
            }
        }
    }

    private func option(_ mode: NoiseMode) -> some View {
        let selected = device.state.noiseMode == mode
        return Button { device.setNoiseMode(mode) } label: {
            HStack(spacing: 10) {
                IconBadge(symbol: mode.symbol, on: selected, pending: selected && device.state.noisePending)
                Text(mode.label).font(.system(size: 13))
                Spacer()
            }
        }
        .buttonStyle(HoverRowStyle())
        .disabled(device.state.noisePending && !selected)
    }
}

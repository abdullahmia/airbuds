// Quick Settings page: a Low Latency tile and device info.

import AirBudsKit
import SwiftUI

struct QuickSettingsView: View {
    @EnvironmentObject var device: EarbudsController

    private var state: DeviceState { device.state }

    var body: some View {
        VStack(spacing: 8) {
            SubpageHeader(title: "Quick Settings")

            if state.capabilities.lowLatency {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    lowLatencyTile
                }
                .padding(.horizontal, 12)
            }

            DeviceInfo()
        }
    }

    private var lowLatencyTile: some View {
        let value = state.quick.lowLatency
        let pending = state.quick.lowLatencyPending
        return Tile(symbol: "bolt.fill", name: "Low Latency",
                    detail: value.map { $0 ? "On" : "Off" } ?? "—",
                    on: value == true, pending: pending) {
            guard let value, !pending else { return }
            device.setLowLatency(!value)
        }
    }
}

// MARK: - Device info

private struct DeviceInfo: View {
    @EnvironmentObject var device: EarbudsController

    var body: some View {
        let state = device.state
        VStack(spacing: 3) {
            Divider().padding(.bottom, 2)
            row("Firmware", state.quick.firmware)
            if let address = state.address, !address.isEmpty { row("Bluetooth Address", address.uppercased()) }
        }
        .padding(.horizontal, 14)
        .padding(.top, 2)
    }

    private func row(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value ?? "—").textSelection(.enabled)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }
}

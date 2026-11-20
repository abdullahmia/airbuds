// Quick Settings page: a Low Latency tile, Automations, Touch Controls,
// Quit, and device info with the earbuds' name (editable here).

import AirBudsKit
import SwiftUI

struct QuickSettingsView: View {
    @EnvironmentObject var device: EarbudsController
    @EnvironmentObject var nav: PanelNavigation

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

            Button { nav.openAutomations() } label: {
                HStack(spacing: 10) {
                    IconBadge(symbol: "app.badge.checkmark")
                    Text("Automations…").font(.system(size: 13))
                    Spacer()
                }
            }
            .buttonStyle(HoverRowStyle())
            .help("Change settings automatically while particular apps are open")

            if state.capabilities.touchControls {
                row("hand.tap", "Touch Controls…", help: "Choose what tapping each earbud does") {
                    nav.page = .touchControls
                }
            }

            Button { NSApp.terminate(nil) } label: {
                HStack(spacing: 10) {
                    IconBadge(symbol: "power")
                    Text("Quit AirBuds").font(.system(size: 13))
                    Spacer()
                }
            }
            .buttonStyle(HoverRowStyle())
            .help("Quit AirBuds")

            DeviceInfo()
        }
    }

    private func row(_ symbol: String, _ title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                IconBadge(symbol: symbol)
                Text(title).font(.system(size: 13))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(HoverRowStyle())
        .help(help)
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
            NameRow()
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

// MARK: - Name

/// The earbuds' name, with a pencil to rename them when they support it.
private struct NameRow: View {
    @EnvironmentObject var device: EarbudsController
    /// The name being typed; nil when not editing.
    @StateObject private var draft = Local<String?>(nil)
    @FocusState private var focused: Bool

    var body: some View {
        let state = device.state
        if let text = draft.value {
            editor(text)
        } else {
            HStack(spacing: 4) {
                Text("Name")
                Spacer()
                Text(state.name ?? "—").textSelection(.enabled).lineLimit(1)
                if state.namePending {
                    ProgressView().controlSize(.small).scaleEffect(0.5).frame(width: 14, height: 14)
                } else if state.capabilities.rename {
                    Button { draft.value = state.name ?? "" } label: {
                        Image(systemName: "pencil").frame(width: 14, height: 14).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Rename")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }

    private func editor(_ text: String) -> some View {
        let valid = JieliCodec.validName(text)
        let bytes: Int = text.trimmingCharacters(in: .whitespacesAndNewlines).utf8.count
        let tooLong: Bool = bytes > JieliCodec.maxNameBytes
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                TextField("Name", text: Binding(get: { draft.value ?? "" }, set: { draft.value = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .focused($focused)
                    .onSubmit { save() }
                Button("Cancel") { draft.value = nil }
                    .controlSize(.small)
                Button("Rename") { save() }
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
                    .disabled(valid == nil)
            }
            Text(tooLong ? "Too long: \(bytes) of \(JieliCodec.maxNameBytes) bytes."
                         : "Other devices see the new name after the earbuds restart.")
                .font(.system(size: 10))
                .foregroundStyle(tooLong ? Color.red : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    private func save() {
        guard let text = draft.value, device.rename(text) else { return }
        draft.value = nil
    }
}

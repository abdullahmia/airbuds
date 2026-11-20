// The popover panel: the main page plus sub-pages that slide in from the right.
// Shared building blocks are in Views/Components.swift.

import AirBudsKit
import SwiftUI

enum PanelPage: Equatable {
    case main, quickSettings, equalizer, battery, touchControls

    /// Where Back (and Esc) goes from this page.
    var parent: PanelPage {
        switch self {
        case .touchControls: return .quickSettings
        default: return .main
        }
    }
}

final class PanelNavigation: ObservableObject {
    @Published var page: PanelPage = .main
    /// Closes the panel and opens the Automations window.
    var openAutomations: () -> Void = {}
}

struct PanelView: View {
    static let width: CGFloat = 300

    @EnvironmentObject var device: EarbudsController
    @EnvironmentObject var nav: PanelNavigation

    var body: some View {
        ZStack {
            switch nav.page {
            case .main:
                MainView().transition(.move(edge: .leading).combined(with: .opacity))
            case .quickSettings:
                QuickSettingsView().transition(.move(edge: .trailing).combined(with: .opacity))
            case .equalizer:
                EqualizerView().transition(.move(edge: .trailing).combined(with: .opacity))
            case .battery:
                BatteryView().transition(.move(edge: .trailing).combined(with: .opacity))
            case .touchControls:
                TouchControlsView().transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(width: Self.width)
        .padding(.vertical, 6)
        .animation(.easeOut(duration: 0.18), value: nav.page)
        .background(
            // Esc goes back one page.
            Button("") { nav.page = nav.page.parent }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
        )
        .onChange(of: device.state.connected) { connected in
            if !connected { nav.page = .main }
        }
    }
}

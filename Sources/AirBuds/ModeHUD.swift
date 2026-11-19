// A small on-screen indicator for changes made without the panel (keyboard
// shortcut, airbuds:// links, automations): it appears under the menu bar icon,
// stays for a moment and fades out. It never takes focus or clicks.

import AppKit
import SwiftUI

struct HUDMessage: Equatable {
    var symbol: String
    var title: String
    var detail: String?
}

final class ModeHUD {
    private static let visible: TimeInterval = 1.4
    private static let fade: TimeInterval = 0.25

    private let model = Local(HUDMessage(symbol: "earbuds", title: ""))
    private lazy var panel: NSPanel = makePanel()
    private let hideTimer = Delayed()

    /// Shows `message` under `anchor` (the status item button), or at the top
    /// right of the main screen if it has no window.
    func show(_ message: HUDMessage, below anchor: NSView?) {
        model.value = message
        let panel = self.panel
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? NSSize(width: 200, height: 60)
        panel.setContentSize(size)
        panel.setFrameOrigin(origin(for: size, below: anchor))

        if !panel.isVisible || panel.alphaValue < 1 {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = Self.fade; panel.animator().alphaValue = 1 }
        }
        hideTimer.schedule(Self.visible) { [weak self] in self?.hide() }
    }

    private func hide() {
        let panel = self.panel
        NSAnimationContext.runAnimationGroup({ $0.duration = Self.fade; panel.animator().alphaValue = 0 },
                                             completionHandler: { if panel.alphaValue == 0 { panel.orderOut(nil) } })
    }

    private func origin(for size: NSSize, below anchor: NSView?) -> NSPoint {
        if let anchor, let window = anchor.window, let screen = window.screen {
            let rect = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            let visible = screen.visibleFrame
            let x: CGFloat = min(max(rect.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
            return NSPoint(x: x, y: rect.minY - size.height - 8)
        }
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        return NSPoint(x: visible.maxX - size.width - 16, y: visible.maxY - size.height - 8)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let hosting = NSHostingView(rootView: HUDView(model: model))
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting
        return panel
    }
}

struct HUDView: View {
    @ObservedObject var model: Local<HUDMessage>

    var body: some View {
        let message = model.value
        HStack(spacing: 10) {
            Image(systemName: message.symbol)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.accentColor))
                .foregroundStyle(Color.white)
            VStack(alignment: .leading, spacing: 1) {
                Text(message.title).font(.system(size: 13, weight: .semibold))
                if let detail = message.detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .fixedSize()
        }
        .padding(.vertical, 10)
        .padding(.leading, 10)
        .padding(.trailing, 16)
        .background(VisualEffect().clipShape(RoundedRectangle(cornerRadius: 14)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.08)))
    }
}

/// The translucent HUD material behind the indicator.
private struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

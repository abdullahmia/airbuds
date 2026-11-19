// Menu bar icon: the SF "earbuds" symbol as a template image, so macOS tints it
// for light and dark menu bars. With Noise Cancellation or Transparency on, the
// mode's symbol (the same one the panel uses) sits to its right.

import AppKit
import AirBudsKit

enum MenuBarIcon {
    static let height: CGFloat = 14
    private static let badgeSize: CGFloat = 10
    private static let gap: CGFloat = 2

    static func make(noiseMode: NoiseMode? = nil) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: height, weight: .regular)
        let base = NSImage(systemSymbolName: "earbuds", accessibilityDescription: "AirBuds")?
            .withSymbolConfiguration(config)
            ?? NSImage(size: NSSize(width: height, height: height))
        base.isTemplate = true

        guard let noiseMode, noiseMode != .off,
              let badge = NSImage(systemSymbolName: noiseMode.symbol, accessibilityDescription: noiseMode.label)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: badgeSize, weight: .medium))
        else { return base }

        let width: CGFloat = base.size.width + gap + badge.size.width
        let size = NSSize(width: width, height: max(base.size.height, badge.size.height))
        let image = NSImage(size: size, flipped: false) { _ in
            base.draw(at: NSPoint(x: 0, y: (size.height - base.size.height) / 2),
                      from: .zero, operation: .sourceOver, fraction: 1)
            badge.draw(at: NSPoint(x: base.size.width + gap, y: (size.height - badge.size.height) / 2),
                       from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "AirBuds, \(noiseMode.label)"
        return image
    }
}

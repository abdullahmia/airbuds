// Menu bar icon: the SF "earbuds" symbol as a template image, so macOS tints it
// for light and dark menu bars.

import AppKit

enum MenuBarIcon {
    static let height: CGFloat = 14

    static func make() -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: height, weight: .regular)
        let image = NSImage(systemSymbolName: "earbuds", accessibilityDescription: "AirBuds")?
            .withSymbolConfiguration(config)
            ?? NSImage(size: NSSize(width: height, height: height))
        image.isTemplate = true
        return image
    }
}

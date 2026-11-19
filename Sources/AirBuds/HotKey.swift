// A system-wide keyboard shortcut through Carbon's RegisterEventHotKey, which
// works from any app without Accessibility permission.

import Carbon.HIToolbox

final class HotKey {
    /// ⌃⌥N
    static let noiseControl = (keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(controlKey | optionKey), display: "⌃⌥N")

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    /// nil if the shortcut is taken by another app (or registration fails otherwise).
    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().action()
            return noErr
        }, 1, &pressed, me, &handler)
        guard installed == noErr else { return nil }

        let id = EventHotKeyID(signature: OSType(0x4142_5544), id: 1) // 'ABUD'
        let registered = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
        guard registered == noErr else {
            Log.info("Could not register the keyboard shortcut (error \(registered)); another app may use it")
            RemoveEventHandler(handler)
            handler = nil
            return nil
        }
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}

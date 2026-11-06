import AppKit

/// Tracks one physical hotkey press. A combined shortcut cancels it until release.
struct HotkeyGesture {
    enum Action: Equatable {
        case press
        case release
        case cancel
    }

    private(set) var isHeld = false
    private var isCancelled = false

    mutating func handle(
        shortcut: KeyShortcut,
        type: NSEvent.EventType,
        keyCode: UInt16,
        flags: NSEvent.ModifierFlags,
        isARepeat: Bool = false
    ) -> Action? {
        if isHeld {
            if shortcut.matchesRelease(type: type, keyCode: keyCode, flags: flags) {
                isHeld = false
                defer { isCancelled = false }
                return isCancelled ? nil : .release
            }
            if !isCancelled && keyCode != shortcut.keyCode
                && (type == .keyDown || type == .flagsChanged)
            {
                isCancelled = true
                return .cancel
            }
            return nil
        }
        if shortcut.matchesPress(type: type, keyCode: keyCode, flags: flags, isARepeat: isARepeat) {
            isHeld = true
            return .press
        }
        return nil
    }
}

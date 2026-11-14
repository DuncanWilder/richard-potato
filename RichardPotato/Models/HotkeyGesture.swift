import AppKit

/// Tracks one physical hotkey press and rejects shortcut chords during the guard window.
struct HotkeyGesture {
    enum Action: Equatable {
        case press
        case release
        case cancel
    }

    static let guardDuration: TimeInterval = 0.4

    private var pressedAt: TimeInterval = 0
    private(set) var isHeld = false
    private var isCancelled = false

    mutating func handle(
        shortcut: KeyShortcut,
        type: NSEvent.EventType,
        keyCode: UInt16,
        flags: NSEvent.ModifierFlags,
        isARepeat: Bool = false,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> Action? {
        if isHeld {
            if shortcut.matchesRelease(type: type, keyCode: keyCode, flags: flags) {
                isHeld = false
                defer { isCancelled = false }
                return isCancelled ? nil : .release
            }
            if !isCancelled && now - pressedAt < Self.guardDuration
                && keyCode != shortcut.keyCode
                && (type == .keyDown || type == .flagsChanged)
            {
                isCancelled = true
                return .cancel
            }
            return nil
        }
        if shortcut.matchesPress(type: type, keyCode: keyCode, flags: flags, isARepeat: isARepeat) {
            pressedAt = now
            isHeld = true
            return .press
        }
        return nil
    }
}

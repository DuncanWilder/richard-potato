import AppKit
import Testing

@testable import RichardPotato

@Suite("Hotkey gestures")
struct HotkeyGestureTests {
    private let command = KeyShortcut(
        keyCode: 55, modifiers: NSEvent.ModifierFlags.command.rawValue, isModifierOnly: true)

    @Test("A modifier alone presses and releases")
    func modifierAlone() {
        var gesture = HotkeyGesture()
        #expect(
            gesture.handle(shortcut: command, type: .flagsChanged, keyCode: 55, flags: .command)
                == .press)
        #expect(
            gesture.handle(shortcut: command, type: .flagsChanged, keyCode: 55, flags: [])
                == .release)
        #expect(!gesture.isHeld)
    }

    @Test(
        "Space cancels a modifier and release cannot commit text",
        arguments: [
            KeyShortcut(
                keyCode: 55, modifiers: NSEvent.ModifierFlags.command.rawValue, isModifierOnly: true
            ),
            KeyShortcut(
                keyCode: 59, modifiers: NSEvent.ModifierFlags.control.rawValue, isModifierOnly: true
            ),
            KeyShortcut.default,
        ])
    func combinedShortcut(shortcut: KeyShortcut) {
        var gesture = HotkeyGesture()
        _ = gesture.handle(
            shortcut: shortcut, type: .flagsChanged, keyCode: shortcut.keyCode,
            flags: shortcut.modifierFlags)
        #expect(
            gesture.handle(
                shortcut: shortcut, type: .keyDown, keyCode: 49, flags: shortcut.modifierFlags)
                == .cancel)
        #expect(
            gesture.handle(
                shortcut: shortcut, type: .keyDown, keyCode: 49, flags: shortcut.modifierFlags,
                isARepeat: true) == nil)
        #expect(
            gesture.handle(
                shortcut: shortcut, type: .keyUp, keyCode: 49, flags: shortcut.modifierFlags) == nil
        )
        #expect(
            gesture.handle(
                shortcut: shortcut, type: .flagsChanged, keyCode: shortcut.keyCode, flags: [])
                == nil)
        #expect(!gesture.isHeld)
        #expect(
            gesture.handle(
                shortcut: shortcut, type: .flagsChanged, keyCode: shortcut.keyCode,
                flags: shortcut.modifierFlags)
                == .press)
    }

    @Test("Another modifier cancels the held hotkey")
    func additionalModifier() {
        var gesture = HotkeyGesture()
        _ = gesture.handle(shortcut: command, type: .flagsChanged, keyCode: 55, flags: .command)
        #expect(
            gesture.handle(
                shortcut: command, type: .flagsChanged, keyCode: 56,
                flags: [.command, .shift]) == .cancel)
        #expect(
            gesture.handle(shortcut: command, type: .flagsChanged, keyCode: 56, flags: .command)
                == nil)
        #expect(
            gesture.handle(shortcut: command, type: .flagsChanged, keyCode: 55, flags: []) == nil)
    }

    @Test("A key shortcut ignores its own repeats but cancels for another key")
    func keyShortcut() {
        let shortcut = KeyShortcut(keyCode: 40, modifiers: 0, isModifierOnly: false)
        var gesture = HotkeyGesture()
        #expect(
            gesture.handle(shortcut: shortcut, type: .keyDown, keyCode: 40, flags: []) == .press)
        #expect(
            gesture.handle(
                shortcut: shortcut, type: .keyDown, keyCode: 40, flags: [],
                isARepeat: true) == nil)
        #expect(
            gesture.handle(shortcut: shortcut, type: .keyDown, keyCode: 0, flags: []) == .cancel)
        #expect(
            gesture.handle(shortcut: shortcut, type: .keyUp, keyCode: 40, flags: []) == nil)
    }
    @Test(
        "Keys and modifiers after the guard cannot cancel or suppress release",
        arguments: [NSEvent.EventType.keyDown, .flagsChanged])
    func lateKey(type: NSEvent.EventType) {
        var gesture = HotkeyGesture()
        _ = gesture.handle(
            shortcut: command, type: .flagsChanged, keyCode: 55,
            flags: .command, now: 10)
        #expect(
            gesture.handle(
                shortcut: command, type: type, keyCode: 56,
                flags: [.command, .shift], now: 10 + HotkeyGesture.guardDuration + 0.001) == nil)
        #expect(
            gesture.handle(
                shortcut: command, type: .flagsChanged, keyCode: 55,
                flags: [], now: 11) == .release)
    }

    @Test("A key just inside the guard cancels")
    func insideDeadline() {
        var gesture = HotkeyGesture()
        _ = gesture.handle(
            shortcut: command, type: .flagsChanged, keyCode: 55,
            flags: .command, now: 10)
        #expect(
            gesture.handle(
                shortcut: command, type: .keyDown, keyCode: 49,
                flags: .command, now: 10 + HotkeyGesture.guardDuration - 0.001) == .cancel)
    }

}

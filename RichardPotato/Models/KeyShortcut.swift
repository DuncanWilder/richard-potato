import AppKit
import Foundation

struct KeyShortcut: Equatable, Codable {
    var keyCode: UInt16
    var modifiers: UInt
    var isModifierOnly: Bool

    static let meaningfulFlags: NSEvent.ModifierFlags = [.command, .shift, .option, .control]

    static let `default` = KeyShortcut(
        keyCode: 61,
        modifiers: NSEvent.ModifierFlags.option.rawValue,
        isModifierOnly: true
    )

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers).intersection(Self.meaningfulFlags)
    }

    var displayName: String {
        let mods = modifierFlags
        var parts: [String] = []
        if mods.contains(.control) { parts.append("Control") }
        if mods.contains(.option) { parts.append("Option") }
        if mods.contains(.shift) { parts.append("Shift") }
        if mods.contains(.command) { parts.append("Command") }

        if isModifierOnly {
            if let side = Self.modifierKeyName(keyCode: keyCode) {
                return side
            }
            return parts.isEmpty ? "Unset" : parts.joined(separator: " + ")
        }

        let key = Self.keyName(keyCode: keyCode)
        if parts.isEmpty {
            return key
        }
        return (parts + [key]).joined(separator: " + ")
    }

    static func from(event: NSEvent) -> KeyShortcut? {
        if event.type == .flagsChanged {
            let flags = event.modifierFlags.intersection(meaningfulFlags)
            guard !flags.isEmpty else { return nil }
            return KeyShortcut(
                keyCode: UInt16(event.keyCode),
                modifiers: flags.rawValue,
                isModifierOnly: true
            )
        }

        if event.type == .keyDown || event.type == .keyUp {
            if event.keyCode == 53 { return nil }
            return KeyShortcut(
                keyCode: UInt16(event.keyCode),
                modifiers: event.modifierFlags.intersection(meaningfulFlags).rawValue,
                isModifierOnly: false
            )
        }

        return nil
    }

    func matchesPress(_ event: NSEvent) -> Bool {
        // isARepeat raises an ObjC exception for anything that isn't a key event,
        // so it must only be read for keyDown/keyUp.
        let repeated = (event.type == .keyDown || event.type == .keyUp) && event.isARepeat
        return matchesPress(
            type: event.type,
            keyCode: UInt16(event.keyCode),
            flags: event.modifierFlags,
            isARepeat: repeated
        )
    }

    func matchesPress(
        type: NSEvent.EventType,
        keyCode: UInt16,
        flags: NSEvent.ModifierFlags,
        isARepeat: Bool
    ) -> Bool {
        if isModifierOnly {
            guard type == .flagsChanged else { return false }
            guard keyCode == self.keyCode else { return false }
            return flags.intersection(Self.meaningfulFlags) == modifierFlags
        }

        guard type == .keyDown, !isARepeat else { return false }
        return keyCode == self.keyCode
            && flags.intersection(Self.meaningfulFlags) == modifierFlags
    }

    func matchesRelease(_ event: NSEvent) -> Bool {
        matchesRelease(type: event.type, keyCode: UInt16(event.keyCode), flags: event.modifierFlags)
    }

    func matchesRelease(type: NSEvent.EventType, keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        if isModifierOnly {
            guard type == .flagsChanged else { return false }
            guard keyCode == self.keyCode else { return false }
            return !flags.intersection(Self.meaningfulFlags).contains(modifierFlags)
        }

        guard type == .keyUp else { return false }
        return keyCode == self.keyCode
    }

    private static func modifierKeyName(keyCode: UInt16) -> String? {
        switch keyCode {
        case 54: return "Right Command"
        case 55: return "Left Command"
        case 56: return "Left Shift"
        case 57: return "Caps Lock"
        case 58: return "Left Option"
        case 59: return "Left Control"
        case 60: return "Right Shift"
        case 61: return "Right Option"
        case 62: return "Right Control"
        case 63: return "Fn"
        default: return nil
        }
    }

    private static func keyName(keyCode: UInt16) -> String {
        if let modifier = modifierKeyName(keyCode: keyCode) {
            return modifier
        }

        let names: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
            37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space",
            50: "`", 51: "Delete", 53: "Escape", 96: "F5", 97: "F6", 98: "F7",
            99: "F3", 100: "F8", 101: "F9", 103: "F11", 105: "F13", 107: "F14",
            109: "F10", 111: "F12", 113: "F15", 118: "F4", 120: "F2", 122: "F1",
            123: "Left", 124: "Right", 125: "Down", 126: "Up"
        ]
        return names[keyCode] ?? "Key \(keyCode)"
    }
}

enum ActivationMode: String, Codable, CaseIterable, Identifiable {
    case hold
    case toggle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hold: return "Press and hold"
        case .toggle: return "Press to start / stop"
        }
    }
}

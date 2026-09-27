import AppKit
import Foundation

enum InsertionMethod: String, Codable, CaseIterable, Identifiable {
    case paste
    case typing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paste: return "Paste when finished"
        case .typing: return "Type live as you speak"
        }
    }
}

enum TextInserter {
    /// Marks events we post ourselves so the hotkey tap can ignore them.
    static let syntheticEventTag: Int64 = 0x5269_4368

    private static let pasteKeyCode: CGKeyCode = 9

    static func insert(_ string: String, using method: InsertionMethod) {
        guard !string.isEmpty else { return }
        switch method {
        case .paste:
            paste(string)
        case .typing:
            type(string)
        }
    }

    /// Writes the transcript to the clipboard, sends ⌘V to the focused app, then
    /// restores whatever was on the clipboard before. Pasting is effectively
    /// instant regardless of transcript length, unlike synthesised keystrokes.
    private static func paste(_ string: String) {
        let pasteboard = NSPasteboard.general
        let restore = snapshot(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)

        postPasteShortcut()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.restore(restore, to: pasteboard)
        }
    }

    private static func postPasteShortcut() {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: pasteKeyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: pasteKeyCode, keyDown: false) else {
            return
        }

        for event in [down, up] {
            // Force exactly Command: the dictation shortcut's own modifiers may
            // still be physically held when we paste.
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)
        }

        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    contents[type] = data
                }
            }
            return contents
        }
    }

    private static func restore(
        _ items: [[NSPasteboard.PasteboardType: Data]],
        to pasteboard: NSPasteboard
    ) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }

        let restored = items.map { contents -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in contents {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restored)
    }

    private static let deleteKeyCode: CGKeyCode = 51

    /// Sends plain backspaces, used to retract transcript text the recogniser
    /// has revised.
    static func deleteBackward(count: Int) {
        guard count > 0 else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        for _ in 0..<count {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: deleteKeyCode, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: deleteKeyCode, keyDown: false) else {
                return
            }
            for event in [down, up] {
                // The dictation shortcut may still be physically held, and
                // Option+Delete would wipe a whole word.
                event.flags = []
                event.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)
                event.post(tap: .cghidEventTap)
            }
        }
    }

    static func type(_ string: String) {
        let utf16 = Array(string.utf16)
        let source = CGEventSource(stateID: .hidSystemState)
        let chunkSize = 16
        var index = 0
        while index < utf16.count {
            let end = min(index + chunkSize, utf16.count)
            let slice = Array(utf16[index..<end])
            post(slice, source: source, keyDown: true)
            post(slice, source: source, keyDown: false)
            index = end
        }
    }

    private static func post(_ units: [UniChar], source: CGEventSource?, keyDown: Bool) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown) else { return }
        units.withUnsafeBufferPointer { buffer in
            if let base = buffer.baseAddress {
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: base)
            }
        }
        // Held shortcut modifiers must not turn typed text into shortcuts.
        event.flags = []
        event.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)
        event.post(tap: .cghidEventTap)
    }
}

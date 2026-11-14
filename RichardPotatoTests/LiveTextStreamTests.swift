import AppKit
import Testing

@testable import RichardPotato

@Suite("Guarded live text")
@MainActor
struct LiveTextStreamTests {
    @Test("Cancel inside the window discards all buffered text")
    func cancelBuffer() {
        var output: [String] = []
        let stream = LiveTextStream(typeText: { output.append($0) }, deleteText: { _ in })
        stream.begin()
        stream.update(to: " Words spoken immediately")
        #expect(output.isEmpty)
        stream.cancel()
        stream.allowInsertion()
        stream.update(to: "Late result")
        #expect(output.isEmpty)
        #expect(!stream.isActive)
    }

    @Test("The window flushes the latest buffer once, then inserts live before finish")
    func flushAndStream() {
        var output: [String] = []
        var deletions: [Int] = []
        let stream = LiveTextStream(
            typeText: { output.append($0) }, deleteText: { deletions.append($0) })
        stream.begin()
        stream.update(to: " Wrong")
        stream.update(to: " Hello")
        #expect(output.isEmpty)
        stream.allowInsertion()
        #expect(output == ["Hello"])
        stream.allowInsertion()
        stream.update(to: " Hello world")
        #expect(output == ["Hello", " world"])
        #expect(deletions.allSatisfy { $0 == 0 })
        #expect(stream.isActive)
        stream.finish(with: "Hello world!")
        #expect(output == ["Hello", " world", "!"])
        #expect(!stream.isActive)
    }

    @Test("Release before the deadline commits the final text")
    func earlyRelease() {
        var output: [String] = []
        let stream = LiveTextStream(typeText: { output.append($0) }, deleteText: { _ in })
        stream.begin()
        stream.update(to: "Hello")
        stream.finish(with: "Hello")
        #expect(output == ["Hello"])
    }
    @Test("A later key leaves inserted text and the live stream intact")
    func lateKeyKeepsText() {
        var output: [String] = []
        var deleted = 0
        let stream = LiveTextStream(
            typeText: { output.append($0) }, deleteText: { deleted += $0 })
        let shortcut = KeyShortcut(keyCode: 40, modifiers: 0, isModifierOnly: false)
        var gesture = HotkeyGesture()
        _ = gesture.handle(
            shortcut: shortcut, type: .keyDown, keyCode: 40,
            flags: [], now: 0)
        stream.begin()
        stream.update(to: "Hello")
        stream.allowInsertion()
        let action = gesture.handle(
            shortcut: shortcut, type: .keyDown, keyCode: 0,
            flags: [], now: HotkeyGesture.guardDuration + 0.01)
        if action == .cancel { stream.cancel() }
        #expect(action == nil)
        stream.update(to: "Hello world")
        #expect(stream.isActive)
        #expect(output == ["Hello", " world"])
        #expect(deleted == 0)
        #expect(
            gesture.handle(
                shortcut: shortcut, type: .keyUp, keyCode: 40,
                flags: [], now: 1) == .release)
    }

}

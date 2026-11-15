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

    @Test("Only the final live result gets a space, once per session")
    func finalSpace() {
        var output = ""
        let stream = LiveTextStream(
            typeText: { output += $0 },
            deleteText: { output.removeLast($0) })
        for word in ["hello", "world"] {
            stream.begin()
            stream.allowInsertion()
            stream.update(to: String(word.prefix(2)))
            #expect(!output.hasSuffix(" "))
            stream.update(to: word)
            #expect(output.hasSuffix(word))
            stream.finish(with: word, addSpace: true)
            stream.finish(with: word, addSpace: true)
        }
        #expect(output == "hello world ")
    }

    @Test(
        "Final output preserves empty text and existing whitespace",
        arguments: ["", " ", "hello ", "hello\n", "hello\t", "hello\u{00A0}"])
    func unchangedFinalText(text: String) {
        #expect(TextInserter.finalText(text, addSpace: true) == text)
        var output = ""
        let stream = LiveTextStream(
            typeText: { output += $0 },
            deleteText: { output.removeLast($0) })
        stream.begin()
        stream.finish(with: text, addSpace: true)
        #expect(output == String(text.drop { $0.isWhitespace }))
    }

    @Test("The option controls the final paste text")
    func pasteText() {
        #expect(TextInserter.finalText("hello", addSpace: true) == "hello ")
        #expect(TextInserter.finalText("hello", addSpace: false) == "hello")
    }

    @Test("Disabled space leaves live text unchanged")
    func disabledSpace() {
        var output = ""
        let stream = LiveTextStream(typeText: { output += $0 }, deleteText: { _ in })
        stream.begin()
        stream.update(to: "hello")
        stream.finish(with: "hello", addSpace: false)
        #expect(output == "hello")
    }

    @Test(
        "Cancelled sessions cannot add a space or accept a late final result",
        arguments: [false, true])
    func cancelledSpace(guardEnded: Bool) {
        var output = ""
        let stream = LiveTextStream(typeText: { output += $0 }, deleteText: { _ in })
        stream.begin()
        stream.update(to: "hello")
        if guardEnded { stream.allowInsertion() }
        stream.cancel()
        stream.finish(with: "hello", addSpace: true)
        #expect(output == (guardEnded ? "hello" : ""))
        #expect(!stream.isActive)
    }

}

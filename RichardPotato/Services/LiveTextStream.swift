import Foundation

/// Types the transcript into the focused app as it arrives.
///
/// The recogniser keeps revising its volatile tail, so each update is sent as a
/// diff against what has already been typed: backspace the part that changed,
/// then type the replacement.
@MainActor
final class LiveTextStream {
    private var inserted = ""
    private var buffered: String?
    private var isGuarding = false
    private let typeText: (String) -> Void
    private let deleteText: (Int) -> Void

    init(
        typeText: @escaping (String) -> Void = { TextInserter.type($0) },
        deleteText: @escaping (Int) -> Void = { TextInserter.deleteBackward(count: $0) }
    ) {
        self.typeText = typeText
        self.deleteText = deleteText
    }
    /// True between `begin()` and `finish(with:)`, including the tail recorded
    /// after the key is released.
    private(set) var isActive = false

    func begin() {
        inserted = ""
        buffered = nil
        isGuarding = true
        isActive = true
    }

    func allowInsertion() {
        guard isActive else { return }
        isGuarding = false
        if let buffered {
            self.buffered = nil
            update(to: buffered)
        }
    }

    func update(to text: String) {
        guard isActive else { return }
        if isGuarding {
            buffered = text
            return
        }
        let target = Self.trimmingLeadingWhitespace(text)
        guard target != inserted else { return }

        let shared = inserted.commonPrefix(with: target)
        deleteText(inserted.count - shared.count)
        let addition = String(target.dropFirst(shared.count))
        if !addition.isEmpty {
            typeText(addition)
        }
        inserted = target
    }

    func cancel() {
        buffered = nil
        isGuarding = false
        inserted = ""
        isActive = false
    }

    func finish(with text: String) {
        allowInsertion()
        update(to: text)
        inserted = ""
        isActive = false
    }

    /// A transcript often starts with a space, which would otherwise be typed
    /// into the user's text field ahead of the first word.
    private static func trimmingLeadingWhitespace(_ text: String) -> String {
        String(text.drop { $0.isWhitespace })
    }
}

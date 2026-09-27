import Foundation

/// Types the transcript into the focused app as it arrives.
///
/// The recogniser keeps revising its volatile tail, so each update is sent as a
/// diff against what has already been typed: backspace the part that changed,
/// then type the replacement.
@MainActor
final class LiveTextStream {
    private var inserted = ""
    /// True between `begin()` and `finish(with:)`, including the tail recorded
    /// after the key is released.
    private(set) var isActive = false

    func begin() {
        inserted = ""
        isActive = true
    }

    func update(to text: String) {
        let target = Self.trimmingLeadingWhitespace(text)
        guard target != inserted else { return }

        let shared = inserted.commonPrefix(with: target)
        TextInserter.deleteBackward(count: inserted.count - shared.count)
        let addition = String(target.dropFirst(shared.count))
        if !addition.isEmpty {
            TextInserter.type(addition)
        }
        inserted = target
    }

    func finish(with text: String) {
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

import Foundation

struct CaptureSession: Equatable {
    private(set) var isActive = false
    private(set) var finals = ""
    private(set) var volatile = ""

    var displayedText: String {
        finals + volatile
    }

    var committedText: String {
        let combined = finals + volatile
        return combined.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    mutating func begin() {
        isActive = true
        finals = ""
        volatile = ""
    }

    mutating func ingest(text: String, isVolatile: Bool) {
        guard isActive else { return }
        if isVolatile {
            volatile = text
        } else {
            finals += text
            volatile = ""
        }
    }

    mutating func end() -> String {
        let text = committedText
        isActive = false
        volatile = ""
        return text
    }
}

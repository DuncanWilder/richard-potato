import OSLog

enum Log {
    static let hotkey = Logger(subsystem: "com.local.RichardPotato", category: "hotkey")
    static let dictation = Logger(subsystem: "com.local.RichardPotato", category: "dictation")
}

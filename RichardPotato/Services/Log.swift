import OSLog

enum Log {
    static let hotkey = Logger(subsystem: "com.duncanwilder.RichardPotato", category: "hotkey")
    static let dictation = Logger(subsystem: "com.duncanwilder.RichardPotato", category: "dictation")
}

import AppKit
import Foundation

struct TextCorrection: Codable, Identifiable, Equatable {
    var id = UUID()
    var heard: String
    var written: String
}

@MainActor
final class PreferencesStore: ObservableObject {
    @Published var shortcut: KeyShortcut
    @Published var activationMode: ActivationMode
    @Published var microphoneUID: String?
    @Published var insertionMethod: InsertionMethod
    @Published var postProcessTranscript: Bool
    @Published var showListeningIndicator: Bool
    @Published var corrections: [TextCorrection]
    @Published var isRecording = false

    private let shortcutKey = "shortcut"
    private let modeKey = "activationMode"
    private let microphoneKey = "microphoneUID"
    private let insertionKey = "insertionMethod"
    private let postProcessKey = "postProcessTranscript"
    private let indicatorKey = "showListeningIndicator"
    private let correctionsKey = "textCorrections"
    private let liveTypingMigrationKey = "didMigrateToLiveTyping"

    init(defaults: UserDefaults = .standard) {
        if let data = defaults.data(forKey: shortcutKey),
           let decoded = try? JSONDecoder().decode(KeyShortcut.self, from: data) {
            shortcut = decoded
        } else {
            shortcut = .default
        }

        if let raw = defaults.string(forKey: modeKey),
           let mode = ActivationMode(rawValue: raw) {
            activationMode = mode
        } else {
            activationMode = .hold
        }

        microphoneUID = defaults.string(forKey: microphoneKey)
        postProcessTranscript = defaults.bool(forKey: postProcessKey)
        showListeningIndicator = defaults.object(forKey: indicatorKey) as? Bool ?? true
        if let data = defaults.data(forKey: correctionsKey),
           let decoded = try? JSONDecoder().decode([TextCorrection].self, from: data) {
            corrections = decoded
        } else {
            corrections = []
        }

        if let raw = defaults.string(forKey: insertionKey),
           let method = InsertionMethod(rawValue: raw) {
            insertionMethod = method
        } else {
            insertionMethod = .typing
        }

        // Live typing replaced the old paste-at-the-end default, so move
        // existing installs across once. Choosing paste again sticks.
        if !defaults.bool(forKey: liveTypingMigrationKey) {
            defaults.set(true, forKey: liveTypingMigrationKey)
            insertionMethod = .typing
            defaults.set(InsertionMethod.typing.rawValue, forKey: insertionKey)
        }
    }

    func save() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(shortcut) {
            defaults.set(data, forKey: shortcutKey)
        }
        defaults.set(activationMode.rawValue, forKey: modeKey)
        defaults.set(insertionMethod.rawValue, forKey: insertionKey)
        defaults.set(postProcessTranscript, forKey: postProcessKey)
        defaults.set(showListeningIndicator, forKey: indicatorKey)
        if let data = try? JSONEncoder().encode(corrections) {
            defaults.set(data, forKey: correctionsKey)
        }
        if let microphoneUID {
            defaults.set(microphoneUID, forKey: microphoneKey)
        } else {
            defaults.removeObject(forKey: microphoneKey)
        }
    }

    func correct(_ text: String) -> String {
        let rules = corrections.compactMap { rule -> (String, String)? in
            let heard = rule.heard.trimmingCharacters(in: .whitespacesAndNewlines)
            let written = rule.written.trimmingCharacters(in: .whitespacesAndNewlines)
            return heard.isEmpty || written.isEmpty ? nil : (heard, written)
        }.sorted { $0.0.count > $1.0.count }
        guard !rules.isEmpty else { return text }

        let pattern = rules.map { NSRegularExpression.escapedPattern(for: $0.0) }.joined(separator: "|")
        guard let regex = try? NSRegularExpression(
            pattern: "(?<![\\p{L}\\p{N}])(?:\(pattern))(?![\\p{L}\\p{N}])",
            options: [.caseInsensitive]
        ) else { return text }

        let source = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
        var corrected = text
        for match in matches.reversed() {
            let heard = source.substring(with: match.range)
            guard let replacement = rules.first(where: {
                $0.0.compare(heard, options: [.caseInsensitive]) == .orderedSame
            })?.1, let range = Range(match.range, in: corrected) else { continue }
            corrected.replaceSubrange(range, with: replacement)
        }
        return corrected
    }

    func record(_ event: NSEvent) -> Bool {
        guard isRecording else { return false }
        if event.type == .keyDown, event.keyCode == 53 {
            isRecording = false
            return true
        }
        guard let next = KeyShortcut.from(event: event) else { return false }
        if event.type == .keyUp { return false }
        if event.type == .flagsChanged, event.modifierFlags.intersection(KeyShortcut.meaningfulFlags).isEmpty {
            return false
        }
        shortcut = next
        isRecording = false
        save()
        return true
    }
}

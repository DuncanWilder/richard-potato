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

    @Published private(set) var storageMessage: String?
    let fileURL: URL
    private var canSave = true
    private var persistedSettings = StoredSettings()

    init(
        defaults: UserDefaults = .standard, fileURL: URL? = nil,
        legacyDomains: [[String: Any]]? = nil,
        recoveryBuild: String = StoredSettings.currentBuild
    ) {
        self.fileURL = fileURL ?? SettingsFile.defaultURL
        var settings = StoredSettings()
        do {
            let result = try SettingsFile(url: self.fileURL).load()
            settings = result.settings ?? StoredSettings()
            if result.settings == nil || settings.lastRecoveryBuild != recoveryBuild {
                let domains = try legacyDomains ?? LegacySettings.domains(defaults: defaults)
                if result.settings == nil {
                    settings = try StoredSettings.migrate(domains: domains)
                }
                try settings.recoverCorrections(domains: domains, build: recoveryBuild)
                try SettingsFile(url: self.fileURL).save(settings)
            }
            storageMessage = result.message
        } catch {
            canSave = false
            storageMessage =
                "Settings could not be loaded. Changes will not be saved. "
                + error.localizedDescription
        }
        persistedSettings = settings
        shortcut = settings.shortcut
        activationMode = settings.activationMode
        microphoneUID = settings.microphoneUID
        insertionMethod = settings.insertionMethod
        postProcessTranscript = settings.postProcessTranscript
        showListeningIndicator = settings.showListeningIndicator
        corrections = settings.corrections
    }

    func save() {
        guard canSave else { return }
        var settings = persistedSettings
        settings.shortcut = shortcut
        settings.activationMode = activationMode
        settings.microphoneUID = microphoneUID
        settings.insertionMethod = insertionMethod
        settings.postProcessTranscript = postProcessTranscript
        settings.showListeningIndicator = showListeningIndicator
        settings.corrections = corrections
        do {
            try SettingsFile(url: fileURL).save(settings)
            persistedSettings = settings
        } catch {
            storageMessage = "Settings could not be saved. " + error.localizedDescription
        }
    }

    func correct(_ text: String) -> String {
        let rules = corrections.compactMap { rule -> (String, String)? in
            let heard = rule.heard.trimmingCharacters(in: .whitespacesAndNewlines)
            let written = rule.written.trimmingCharacters(in: .whitespacesAndNewlines)
            return heard.isEmpty || written.isEmpty ? nil : (heard, written)
        }.sorted { $0.0.count > $1.0.count }
        guard !rules.isEmpty else { return text }

        let pattern = rules.map { NSRegularExpression.escapedPattern(for: $0.0) }.joined(
            separator: "|")
        guard
            let regex = try? NSRegularExpression(
                pattern: "(?<![\\p{L}\\p{N}])(?:\(pattern))(?![\\p{L}\\p{N}])",
                options: [.caseInsensitive]
            )
        else { return text }

        let source = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
        var corrected = text
        for match in matches.reversed() {
            let heard = source.substring(with: match.range)
            guard
                let replacement = rules.first(where: {
                    $0.0.compare(heard, options: [.caseInsensitive]) == .orderedSame
                })?.1, let range = Range(match.range, in: corrected)
            else { continue }
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
        if event.type == .flagsChanged,
            event.modifierFlags.intersection(KeyShortcut.meaningfulFlags).isEmpty
        {
            return false
        }
        shortcut = next
        isRecording = false
        save()
        return true
    }
}

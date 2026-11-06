import Foundation

/// Version 1 contains all app preferences. Login registration is managed by macOS.
struct StoredSettings: Codable, Equatable {
    var version = 1
    var shortcut = KeyShortcut.default
    var activationMode = ActivationMode.hold
    var microphoneUID: String?
    var insertionMethod = InsertionMethod.typing
    var postProcessTranscript = false
    var showListeningIndicator = true
    var corrections: [TextCorrection] = []

    // Optional fields keep existing version 1 files compatible.
    var lastRecoveryBuild: String?
    var recoveredCorrections: [TextCorrection]?

    static var currentBuild: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "development")"
            + " (\(info["CFBundleVersion"] as? String ?? "0"))"
    }

    /// Import each saved rule once. Keep JSON choices when a phrase has changed.
    mutating func recoverCorrections(domains: [[String: Any]], build: String) throws {
        guard lastRecoveryBuild != build else { return }
        let discovered = try Self.legacyCorrections(domains: domains)
        var recovered = recoveredCorrections ?? []
        for var rule in discovered {
            let seen = recovered.contains { $0.heard == rule.heard && $0.written == rule.written }
            guard !seen else { continue }
            recovered.append(rule)
            let phrase = rule.heard.trimmingCharacters(in: .whitespacesAndNewlines)
            guard
                !corrections.contains(where: {
                    $0.heard.trimmingCharacters(in: .whitespacesAndNewlines)
                        .compare(phrase, options: [.caseInsensitive]) == .orderedSame
                })
            else { continue }
            if corrections.contains(where: { $0.id == rule.id }) { rule.id = UUID() }
            corrections.append(rule)
        }
        recoveredCorrections = recovered
        lastRecoveryBuild = build
    }

    static func migrate(domains: [[String: Any]]) throws -> StoredSettings {
        var settings = StoredSettings()
        func value(_ key: String) -> Any? {
            domains.lazy.compactMap { $0[key] }.first
        }
        if let data = value("shortcut") as? Data {
            settings.shortcut = try JSONDecoder().decode(KeyShortcut.self, from: data)
        }
        if let raw = value("activationMode") as? String {
            guard let mode = ActivationMode(rawValue: raw) else {
                throw SettingsFileError.invalidLegacy
            }
            settings.activationMode = mode
        }
        if let raw = value("insertionMethod") as? String {
            guard let method = InsertionMethod(rawValue: raw) else {
                throw SettingsFileError.invalidLegacy
            }
            settings.insertionMethod = method
        }
        settings.microphoneUID = value("microphoneUID") as? String
        settings.postProcessTranscript = value("postProcessTranscript") as? Bool ?? false
        settings.showListeningIndicator = value("showListeningIndicator") as? Bool ?? true
        settings.corrections = try legacyCorrections(domains: domains)
        settings.recoveredCorrections = settings.corrections
        return settings
    }

    private static func legacyCorrections(domains: [[String: Any]]) throws -> [TextCorrection] {
        var corrections: [TextCorrection] = []
        for domain in domains {
            guard let value = domain["textCorrections"] else { continue }
            guard let data = value as? Data else { throw SettingsFileError.invalidLegacy }
            for var rule in try JSONDecoder().decode([TextCorrection].self, from: data) {
                guard
                    !corrections.contains(where: {
                        $0.heard == rule.heard && $0.written == rule.written
                    })
                else { continue }
                if corrections.contains(where: { $0.id == rule.id }) { rule.id = UUID() }
                corrections.append(rule)
            }
        }
        return corrections
    }
}

enum SettingsFileError: LocalizedError {
    case unsupportedVersion(Int)
    case invalidLegacy
    case recoveryFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "Settings version \(version) needs a newer app. The file was not changed."
        case .invalidLegacy:
            return "The old settings contain invalid data. The old data was not changed."
        case .recoveryFailed(let detail):
            return "No valid settings backup was found. \(detail)"
        }
    }
}

struct SettingsFile {
    let url: URL
    var backupURL: URL { url.appendingPathExtension("bak") }

    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Richard Potato", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    private func decode(_ data: Data) throws -> StoredSettings {
        struct Header: Decodable { let version: Int }
        let decoder = JSONDecoder()
        let version = try decoder.decode(Header.self, from: data).version
        guard version == 1 else { throw SettingsFileError.unsupportedVersion(version) }
        return try decoder.decode(StoredSettings.self, from: data)
    }

    func load() throws -> (settings: StoredSettings?, message: String?) {
        let manager = FileManager.default
        let exists = manager.fileExists(atPath: url.path)
        if exists {
            do {
                return (try decode(Data(contentsOf: url)), nil)
            } catch let error as SettingsFileError {
                // A future format is not a corrupt file. Never downgrade it.
                throw error
            } catch {
                // Keep the original bytes before attempting recovery.
                let preserved = url.deletingLastPathComponent()
                    .appendingPathComponent("settings.invalid-\(UUID().uuidString).json")
                try manager.copyItem(at: url, to: preserved)
                do {
                    let data = try Data(contentsOf: backupURL)
                    let settings = try decode(data)
                    try data.write(to: url, options: .atomic)
                    return (
                        settings,
                        "Settings were restored from the backup. The damaged file is at \(preserved.path)."
                    )
                } catch {
                    throw SettingsFileError.recoveryFailed(
                        "The original file is at \(preserved.path). \(error.localizedDescription)")
                }
            }
        }
        if manager.fileExists(atPath: backupURL.path) {
            let data = try Data(contentsOf: backupURL)
            let settings = try decode(data)
            try data.write(to: url, options: .atomic)
            return (
                settings, "The settings file was missing. Settings were restored from the backup."
            )
        }
        return (nil, nil)
    }

    func save(_ settings: StoredSettings) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(settings)
        let manager = FileManager.default
        try manager.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if manager.fileExists(atPath: url.path) {
            let previous = try Data(contentsOf: url)
            _ = try decode(previous)
            try previous.write(to: backupURL, options: .atomic)
        } else if !manager.fileExists(atPath: backupURL.path) {
            try data.write(to: backupURL, options: .atomic)
        }
        // Foundation writes a temporary file and renames it over the destination.
        try data.write(to: url, options: .atomic)
    }
}

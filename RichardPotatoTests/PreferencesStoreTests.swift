import Foundation
import Testing

@testable import RichardPotato

@Suite("Settings persistence")
struct PreferencesStoreTests {
    private func withFile(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory.appendingPathComponent("settings.json"))
    }

    @Test("All preferences survive copying the file to a new location")
    @MainActor func roundTrip() throws {
        try withFile { url in
            let store = PreferencesStore(fileURL: url, legacyDomains: [])
            store.shortcut = KeyShortcut(keyCode: 0, modifiers: 0, isModifierOnly: false)
            store.activationMode = .toggle
            store.microphoneUID = "test microphone"
            store.insertionMethod = .paste
            store.postProcessTranscript = true
            store.showListeningIndicator = false
            store.corrections = [TextCorrection(heard: "potato", written: "🥔")]
            store.save()
            let copy = url.deletingLastPathComponent().appendingPathComponent("copied.json")
            try FileManager.default.copyItem(at: url, to: copy)
            let restored = PreferencesStore(fileURL: copy, legacyDomains: [])
            #expect(restored.shortcut == store.shortcut)
            #expect(restored.activationMode == .toggle)
            #expect(restored.microphoneUID == "test microphone")
            #expect(restored.insertionMethod == .paste)
            #expect(restored.postProcessTranscript)
            #expect(!restored.showListeningIndicator)
            #expect(restored.corrections == store.corrections)
            #expect(restored.storageMessage == nil)
        }
    }

    @Test("Migration combines both bundle domains without changing legacy data")
    @MainActor func migration() throws {
        let name = "RichardPotatoTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let current = TextCorrection(heard: "one", written: "1")
        let old = TextCorrection(heard: "two", written: "2")
        defaults.set(try JSONEncoder().encode([current]), forKey: "textCorrections")
        defaults.set("paste", forKey: "insertionMethod")
        let before = defaults.persistentDomain(forName: name)!
        let legacy: [String: Any] = ["textCorrections": try JSONEncoder().encode([current, old])]
        try withFile { url in
            let store = PreferencesStore(
                defaults: defaults, fileURL: url,
                legacyDomains: [before, legacy])
            #expect(store.corrections == [current, old])
            #expect(store.insertionMethod == .paste)
            #expect(
                NSDictionary(dictionary: before).isEqual(
                    to: defaults.persistentDomain(forName: name)!))
            let reloaded = PreferencesStore(fileURL: url, legacyDomains: [])
            #expect(reloaded.corrections == [current, old])
        }
    }

    @Test("Missing and damaged primary files recover from a valid backup")
    func recover() throws {
        try withFile { url in
            let file = SettingsFile(url: url)
            var settings = StoredSettings()
            settings.corrections = [TextCorrection(heard: "hello", written: "Hello")]
            try file.save(settings)
            try FileManager.default.removeItem(at: url)
            #expect(try file.load().settings == settings)
            try Data("broken".utf8).write(to: url)
            let recovered = try file.load()
            #expect(recovered.settings == settings)
            #expect(recovered.message != nil)
            let files = try FileManager.default.contentsOfDirectory(
                at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            let preserved = try #require(
                files.first { $0.lastPathComponent.hasPrefix("settings.invalid-") })
            #expect(try String(contentsOf: preserved, encoding: .utf8) == "broken")
        }
    }

    @Test("Unrecoverable settings are preserved and cannot be overwritten")
    @MainActor func protectBrokenFile() throws {
        try withFile { url in
            let broken = Data("broken".utf8)
            try broken.write(to: url)
            let store = PreferencesStore(fileURL: url, legacyDomains: [])
            #expect(store.storageMessage != nil)
            store.corrections = [TextCorrection(heard: "new", written: "New")]
            store.save()
            #expect(try Data(contentsOf: url) == broken)
        }
    }

    @Test("A newer format is never replaced with an older backup")
    @MainActor func protectFutureVersion() throws {
        try withFile { url in
            try SettingsFile(url: url).save(StoredSettings())
            let future = Data("{\"version\":99}".utf8)
            try future.write(to: url)
            let store = PreferencesStore(fileURL: url, legacyDomains: [])
            #expect(store.storageMessage?.contains("newer app") == true)
            store.save()
            #expect(try Data(contentsOf: url) == future)
        }
    }

    @Test("Save keeps the last valid settings as a backup")
    func backup() throws {
        try withFile { url in
            let file = SettingsFile(url: url)
            let original = StoredSettings()
            try file.save(original)
            var changed = original
            changed.activationMode = .toggle
            try file.save(changed)
            try FileManager.default.removeItem(at: url)
            #expect(try file.load().settings == original)
        }
    }

    @Test("A save error is shown and leaves the primary file unchanged")
    @MainActor func saveFailure() throws {
        try withFile { url in
            let store = PreferencesStore(fileURL: url, legacyDomains: [])
            let original = try Data(contentsOf: url)
            let backup = url.appendingPathExtension("bak")
            try FileManager.default.removeItem(at: backup)
            try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: false)
            store.activationMode = .toggle
            store.save()
            #expect(store.storageMessage?.contains("could not be saved") == true)
            #expect(try Data(contentsOf: url) == original)
        }
    }

    @Test("Damage to both files blocks saves and preserves the backup")
    @MainActor func damagedBackup() throws {
        try withFile { url in
            let file = SettingsFile(url: url)
            try file.save(StoredSettings())
            let broken = Data("broken".utf8)
            try broken.write(to: url)
            try broken.write(to: file.backupURL)
            let store = PreferencesStore(fileURL: url, legacyDomains: [])
            #expect(store.storageMessage != nil)
            store.save()
            #expect(try Data(contentsOf: url) == broken)
            #expect(try Data(contentsOf: file.backupURL) == broken)
        }
    }

    @Test("Updates recover new rules once and preserve edits and deletions")
    @MainActor func updateRecovery() throws {
        try withFile { url in
            let old = TextCorrection(heard: "old", written: "Old")
            let extra = TextCorrection(heard: "extra", written: "Extra")
            let later = TextCorrection(heard: "later", written: "Later")
            let initial = ["textCorrections": try JSONEncoder().encode([old])]
            let first = PreferencesStore(fileURL: url, legacyDomains: [initial], recoveryBuild: "1")
            first.corrections = []
            first.save()
            let additional = ["textCorrections": try JSONEncoder().encode([old, extra])]
            let sameBuild = PreferencesStore(
                fileURL: url, legacyDomains: [additional], recoveryBuild: "1")
            #expect(sameBuild.corrections.isEmpty)
            let update = PreferencesStore(
                fileURL: url, legacyDomains: [additional], recoveryBuild: "2")
            #expect(update.corrections == [extra])
            update.corrections[0].written = "My edit"
            update.save()
            let next = ["textCorrections": try JSONEncoder().encode([old, extra, later])]
            let nextUpdate = PreferencesStore(
                fileURL: url, legacyDomains: [next], recoveryBuild: "3")
            #expect(nextUpdate.corrections.map(\.written) == ["My edit", "Later"])
            #expect(try SettingsFile(url: url).load().settings?.lastRecoveryBuild == "3")
        }
    }

    @Test("Recovery adds to an existing JSON file without replacing current choices")
    @MainActor func existingJSONRecovery() throws {
        try withFile { url in
            var settings = StoredSettings()
            settings.activationMode = .toggle
            settings.corrections = [TextCorrection(heard: "CLAUDE", written: "My choice")]
            try SettingsFile(url: url).save(settings)
            let legacy = [
                TextCorrection(heard: "claude", written: "Claude"),
                TextCorrection(heard: "pool request", written: "pull request"),
            ]
            let store = PreferencesStore(
                fileURL: url,
                legacyDomains: [["textCorrections": try JSONEncoder().encode(legacy)]],
                recoveryBuild: "2")
            #expect(store.activationMode == .toggle)
            #expect(store.corrections.map(\.written) == ["My choice", "pull request"])
        }
    }

    @Test("Discovery reads alternate app and ByHost plists and skips other apps")
    func discoverDefaults() throws {
        try withFile { url in
            let directory = url.deletingLastPathComponent()
            let host = directory.appendingPathComponent("ByHost")
            try FileManager.default.createDirectory(at: host, withIntermediateDirectories: true)
            let rules = [TextCorrection(heard: "found", written: "Found")]
            let data = try PropertyListSerialization.data(
                fromPropertyList: ["textCorrections": JSONEncoder().encode(rules)],
                format: .binary, options: 0)
            try data.write(
                to: directory.appendingPathComponent("com.local.RichardPotato.dev.plist"))
            try data.write(to: host.appendingPathComponent("com.local.RichardPotato.host-id.plist"))
            try Data("invalid plist".utf8).write(
                to: directory.appendingPathComponent("other-app.plist"))
            let name = "RichardPotatoTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            let domains = try LegacySettings.domains(
                defaults: defaults, preferencesDirectory: directory)
            #expect(
                domains.filter {
                    guard let data = $0["textCorrections"] as? Data else { return false }
                    return (try? JSONDecoder().decode([TextCorrection].self, from: data)) == rules
                }.count == 2)
        }
    }

    @Test("Invalid legacy replacements stop migration without writing empty settings")
    @MainActor func invalidMigration() throws {
        try withFile { url in
            let store = PreferencesStore(
                fileURL: url,
                legacyDomains: [["textCorrections": Data("broken".utf8)]])
            #expect(store.storageMessage != nil)
            store.save()
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }
}

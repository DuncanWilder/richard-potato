import Foundation

/// Read only app-specific defaults. Never change these recovery sources.
struct LegacySettings {
    static func domains(
        defaults: UserDefaults,
        preferencesDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences", isDirectory: true)
    ) throws -> [[String: Any]] {
        let known = ["com.duncanwilder.RichardPotato", "com.local.RichardPotato", "RichardPotato"]
        var domains = [defaults.dictionaryRepresentation()]
        domains += known.compactMap { defaults.persistentDomain(forName: $0) }
        // Also inspect app-specific plist files, including alternate development
        // domains and ByHost files that the current defaults domain cannot see.
        let manager = FileManager.default
        for directory in [
            preferencesDirectory, preferencesDirectory.appendingPathComponent("ByHost"),
        ] {
            guard manager.fileExists(atPath: directory.path) else { continue }
            let files = try manager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            ).sorted { $0.path < $1.path }
            for file in files where file.pathExtension == "plist" {
                let name = file.deletingPathExtension().lastPathComponent.lowercased()
                guard
                    known.contains(where: {
                        name == $0.lowercased() || name.hasPrefix($0.lowercased() + ".")
                    })
                else { continue }
                let data = try Data(contentsOf: file)
                if let domain = try PropertyListSerialization.propertyList(
                    from: data, format: nil) as? [String: Any]
                {
                    domains.append(domain)
                }
            }
        }
        return domains
    }
}

import Foundation

/// Persists dictation session metrics locally. Never stores transcripts or audio.
@MainActor
final class AnalyticsStore: ObservableObject {
    static let shared = AnalyticsStore()

    @Published private(set) var events: [DictationAnalyticsEvent] = []

    private let fileURL: URL
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let directory = support.appendingPathComponent("com.local.RichardPotato", isDirectory: true)
            self.fileURL = directory.appendingPathComponent("analytics.json")
        }
        load()
    }

    func record(startedAt: Date, endedAt: Date, transcript: String) {
        let duration = max(0, endedAt.timeIntervalSince(startedAt))
        let event = DictationAnalyticsEvent(
            startedAt: startedAt,
            durationSeconds: duration,
            wordCount: AnalyticsAggregator.wordCount(in: transcript)
        )
        events.append(event)
        save()
    }

    func reset() {
        events = []
        save()
    }

    func totals(range: AnalyticsRange) -> AnalyticsTotals {
        AnalyticsAggregator.totals(for: AnalyticsAggregator.filter(events, range: range))
    }

    func dayBuckets(range: AnalyticsRange) -> [DayBucket] {
        AnalyticsAggregator.byDay(events, range: range)
    }

    func hourBuckets(range: AnalyticsRange) -> [HourBucket] {
        AnalyticsAggregator.byHourOfDay(events, range: range)
    }

    func busiestHour(range: AnalyticsRange) -> HourBucket? {
        AnalyticsAggregator.busiestHour(in: hourBuckets(range: range))
    }

    private func load() {
        let fm = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: directory.path) {
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        guard fm.fileExists(atPath: fileURL.path) else {
            events = []
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            events = try decoder.decode([DictationAnalyticsEvent].self, from: data)
        } catch {
            Log.dictation.error("Failed to load analytics: \(error.localizedDescription, privacy: .public)")
            events = []
        }
    }

    private func save() {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let data = try encoder.encode(events)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            Log.dictation.error("Failed to save analytics: \(error.localizedDescription, privacy: .public)")
        }
    }
}

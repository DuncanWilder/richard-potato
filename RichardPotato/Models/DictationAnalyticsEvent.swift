import Foundation

/// One completed dictation session. Transcript text is never stored.
struct DictationAnalyticsEvent: Codable, Equatable, Identifiable {
    var id: UUID
    var startedAt: Date
    /// Wall-clock mic-open time, including the post-release tail.
    var durationSeconds: Double
    var wordCount: Int
    /// Always true today; reserved if we later ignore aborted starts.
    var initiated: Bool

    init(
        id: UUID = UUID(),
        startedAt: Date,
        durationSeconds: Double,
        wordCount: Int,
        initiated: Bool = true
    ) {
        self.id = id
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.wordCount = wordCount
        self.initiated = initiated
    }

    var endedAt: Date {
        startedAt.addingTimeInterval(durationSeconds)
    }
}

enum AnalyticsRange: String, CaseIterable, Identifiable {
    case last7Days
    case last30Days
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .last7Days: return "Last 7 days"
        case .last30Days: return "Last 30 days"
        case .all: return "All time"
        }
    }

    /// Inclusive lower bound for filtering, or nil for no bound.
    func startDate(relativeTo now: Date = Date(), calendar: Calendar = .current) -> Date? {
        switch self {
        case .last7Days:
            return calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))
        case .last30Days:
            return calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now))
        case .all:
            return nil
        }
    }
}

struct AnalyticsTotals: Equatable {
    var sessions: Int
    var words: Int
    var durationSeconds: Double

    static let zero = AnalyticsTotals(sessions: 0, words: 0, durationSeconds: 0)
}

struct DayBucket: Equatable, Identifiable {
    var day: Date
    var sessions: Int
    var words: Int
    var durationSeconds: Double

    var id: Date { day }
}

struct HourBucket: Equatable, Identifiable {
    /// 0…23 in the user's local calendar.
    var hour: Int
    var sessions: Int
    var words: Int
    var durationSeconds: Double

    var id: Int { hour }

    var label: String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("j")
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        return formatter.string(from: date)
    }
}

enum AnalyticsAggregator {
    static func wordCount(in text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    static func filter(
        _ events: [DictationAnalyticsEvent],
        range: AnalyticsRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DictationAnalyticsEvent] {
        guard let start = range.startDate(relativeTo: now, calendar: calendar) else {
            return events
        }
        return events.filter { $0.startedAt >= start }
    }

    static func totals(for events: [DictationAnalyticsEvent]) -> AnalyticsTotals {
        events.reduce(into: .zero) { totals, event in
            if event.initiated { totals.sessions += 1 }
            totals.words += event.wordCount
            totals.durationSeconds += event.durationSeconds
        }
    }

    /// One bucket per calendar day in the range (inclusive). Empty days are zeroed.
    static func byDay(
        _ events: [DictationAnalyticsEvent],
        range: AnalyticsRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DayBucket] {
        let filtered = filter(events, range: range, now: now, calendar: calendar)
        let endDay = calendar.startOfDay(for: now)
        let startDay: Date
        if let bound = range.startDate(relativeTo: now, calendar: calendar) {
            startDay = calendar.startOfDay(for: bound)
        } else if let earliest = filtered.map(\.startedAt).min() {
            startDay = calendar.startOfDay(for: earliest)
        } else {
            startDay = endDay
        }

        var map: [Date: DayBucket] = [:]
        var cursor = startDay
        while cursor <= endDay {
            map[cursor] = DayBucket(day: cursor, sessions: 0, words: 0, durationSeconds: 0)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        for event in filtered {
            let day = calendar.startOfDay(for: event.startedAt)
            guard var bucket = map[day] else { continue }
            if event.initiated { bucket.sessions += 1 }
            bucket.words += event.wordCount
            bucket.durationSeconds += event.durationSeconds
            map[day] = bucket
        }

        return map.values.sorted { $0.day < $1.day }
    }

    /// 24 hour-of-day buckets. Session/word counts attribute to the start hour;
    /// duration is split across hours the mic was open.
    static func byHourOfDay(
        _ events: [DictationAnalyticsEvent],
        range: AnalyticsRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [HourBucket] {
        let filtered = filter(events, range: range, now: now, calendar: calendar)
        var buckets = (0..<24).map {
            HourBucket(hour: $0, sessions: 0, words: 0, durationSeconds: 0)
        }

        for event in filtered {
            let startHour = calendar.component(.hour, from: event.startedAt)
            if event.initiated {
                buckets[startHour].sessions += 1
            }
            buckets[startHour].words += event.wordCount

            for (hour, seconds) in durationByHour(event: event, calendar: calendar) {
                buckets[hour].durationSeconds += seconds
            }
        }

        return buckets
    }

    static func busiestHour(in buckets: [HourBucket]) -> HourBucket? {
        buckets.max { lhs, rhs in
            if lhs.durationSeconds != rhs.durationSeconds {
                return lhs.durationSeconds < rhs.durationSeconds
            }
            return lhs.sessions < rhs.sessions
        }.flatMap { best in
            best.durationSeconds > 0 || best.sessions > 0 ? best : nil
        }
    }

    /// Splits mic-open duration across local hour boundaries.
    static func durationByHour(
        event: DictationAnalyticsEvent,
        calendar: Calendar = .current
    ) -> [(hour: Int, seconds: Double)] {
        guard event.durationSeconds > 0 else { return [] }

        var result: [(hour: Int, seconds: Double)] = []
        var cursor = event.startedAt
        let end = event.endedAt

        while cursor < end {
            let hour = calendar.component(.hour, from: cursor)
            let hourStart = calendar.dateInterval(of: .hour, for: cursor)?.start ?? cursor
            let nextHour = calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? end
            let sliceEnd = min(nextHour, end)
            let seconds = sliceEnd.timeIntervalSince(cursor)
            if seconds > 0 {
                result.append((hour, seconds))
            }
            cursor = sliceEnd
        }

        return result
    }
}

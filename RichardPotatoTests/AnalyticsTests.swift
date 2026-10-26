import Foundation
import Testing

@testable import RichardPotato

@Suite("Analytics")
struct AnalyticsTests {
    @Test("Count words across spaces and line breaks")
    func countWords() {
        #expect(AnalyticsAggregator.wordCount(in: "  Hello\tworld\nagain  ") == 3)
        #expect(AnalyticsAggregator.wordCount(in: " \n\t") == 0)
    }

    @Test("Split duration at midnight without counting a second session")
    func splitAcrossMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(
            from: DateComponents(year: 2026, month: 10, day: 26, hour: 23, minute: 59))!
        let event = DictationAnalyticsEvent(startedAt: start, durationSeconds: 120, wordCount: 5)
        let hours = AnalyticsAggregator.byHourOfDay([event], range: .all, calendar: calendar)
        #expect(hours[23].sessions == 1)
        #expect(hours[23].words == 5)
        #expect(hours[23].durationSeconds == 60)
        #expect(hours[0].sessions == 0)
        #expect(hours[0].durationSeconds == 60)
        #expect(hours.reduce(0) { $0 + $1.durationSeconds } == 120)
    }

    @Test("Include the first day of a seven day range and fill empty days")
    func filterDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 12))!
        let boundary = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20))!
        let included = DictationAnalyticsEvent(
            startedAt: boundary, durationSeconds: 10, wordCount: 2)
        let excluded = DictationAnalyticsEvent(
            startedAt: boundary.addingTimeInterval(-1), durationSeconds: 5, wordCount: 1)
        let days = AnalyticsAggregator.byDay(
            [excluded, included], range: .last7Days, now: now, calendar: calendar)
        #expect(days.count == 7)
        #expect(days.first?.sessions == 1)
        #expect(days.last?.sessions == 0)
        #expect(days.reduce(0) { $0 + $1.words } == 2)
    }
}

import Charts
import SwiftUI

struct AnalyticsView: View {
    @ObservedObject var analytics: AnalyticsStore

    @State private var range: AnalyticsRange = .last7Days
    @State private var chartMode: ChartMode = .day
    @State private var confirmReset = false
    @State private var hoveredDay: Date?
    @State private var hoveredHour: Int?
    @State private var hoveredActivityDay: Date?

    private enum ChartMode: String, CaseIterable, Identifiable {
        case day
        case hour

        var id: String { rawValue }

        var title: String {
            switch self {
            case .day: return "Day"
            case .hour: return "Hour"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                activityHeatmap

                Picker("Range", selection: $range) {
                    ForEach(AnalyticsRange.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)

                Text("Analytics for \(periodTitle)")
                    .font(.headline)

                totalsRow

                Picker("Breakdown", selection: $chartMode) {
                    ForEach(ChartMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                chart
                    .frame(height: 220)

                if chartMode == .hour, let busiest = analytics.busiestHour(range: range) {
                    Text("Busiest hour: \(busiest.label)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Stored on this Mac only. No transcripts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset stats…") {
                        confirmReset = true
                    }
                    .disabled(analytics.events.isEmpty)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 520, minHeight: 420)
        .onChange(of: range) { _, _ in
            hoveredDay = nil
            hoveredHour = nil
        }
        .confirmationDialog(
            "Reset all analytics?",
            isPresented: $confirmReset,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                analytics.reset()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears local session counts, word totals, and voice time. It cannot be undone.")
        }
    }

    private var totals: AnalyticsTotals {
        analytics.totals(range: range)
    }

    private var periodTitle: String {
        switch range {
        case .last7Days: return "last 7 days"
        case .last30Days: return "last 30 days"
        case .all: return "all time"
        }
    }

    private var totalsRow: some View {
        HStack(spacing: 12) {
            totalCard(title: "Sessions", value: "\(totals.sessions)")
            totalCard(title: "Words", value: totals.words.formatted())
            totalCard(title: "Voice time", value: Self.formatDuration(totals.durationSeconds))
        }
    }

    private func totalCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var chart: some View {
        switch chartMode {
        case .day: dayChart
        case .hour: hourChart
        }
    }

    private var activityHeatmap: some View {
        var calendar = Calendar.current
        calendar.firstWeekday = 1
        let lastDay = calendar.startOfDay(for: Date())
        let firstDay = calendar.date(byAdding: .day, value: -364, to: lastDay) ?? lastDay
        let firstWeek = calendar.dateInterval(of: .weekOfYear, for: firstDay)?.start ?? firstDay
        let dayCount = calendar.dateComponents([.day], from: firstWeek, to: lastDay).day ?? 0
        let weekCount = max(1, dayCount / 7 + 1)
        let bucketByDay = Dictionary(uniqueKeysWithValues: analytics.dayBuckets(range: .all)
            .filter { $0.day >= firstDay && $0.day <= lastDay }
            .map { ($0.day, $0) })
        let weekdayLabels = calendar.veryShortStandaloneWeekdaySymbols
        let labelWidth: CGFloat = 14
        let labelGap: CGFloat = 6
        let columnGap: CGFloat = 2
        let rowGap: CGFloat = 3
        let headerHeight: CGFloat = 16
        let squareSize: CGFloat = 12
        let gridHeight = headerHeight + 7 * squareSize + 6 * rowGap

        return VStack(alignment: .leading, spacing: 0) {
            Text("Sessions per day")
                .font(.subheadline.weight(.semibold))
                .padding(.bottom, 8)

            GeometryReader { geometry in
                let availableWidth = geometry.size.width - labelWidth - labelGap
                let visibleWeeks = min(weekCount, max(1, Int(
                    (availableWidth + columnGap) / (squareSize + columnGap)
                )))
                let firstVisibleWeek = weekCount - visibleWeeks
                let gridWidth = CGFloat(visibleWeeks) * squareSize
                    + CGFloat(visibleWeeks - 1) * columnGap
                let blockWidth = labelWidth + labelGap + gridWidth
                let blockX = max(0, geometry.size.width - blockWidth)
                ZStack(alignment: .topLeading) {
                    HStack(alignment: .top, spacing: labelGap) {
                        VStack(spacing: rowGap) {
                            Color.clear.frame(width: labelWidth, height: headerHeight)
                            ForEach(0..<7, id: \.self) { day in
                                Text(weekdayLabels[(calendar.firstWeekday - 1 + day) % 7])
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: labelWidth, height: squareSize)
                            }
                        }

                        HStack(alignment: .top, spacing: columnGap) {
                            ForEach(firstVisibleWeek..<weekCount, id: \.self) { week in
                                heatmapWeek(
                                    week,
                                    firstVisibleWeek: firstVisibleWeek,
                                    firstWeek: firstWeek,
                                    firstDay: firstDay,
                                    lastDay: lastDay,
                                    buckets: bucketByDay,
                                    calendar: calendar,
                                    squareSize: squareSize,
                                    rowGap: rowGap,
                                    headerHeight: headerHeight
                                )
                            }
                        }
                    }
                    .offset(x: blockX)

                    if let hoveredActivityDay,
                       let dayOffset = calendar.dateComponents(
                           [.day], from: firstWeek, to: hoveredActivityDay
                       ).day, dayOffset >= 0,
                       dayOffset / 7 >= firstVisibleWeek {
                        let bucket = bucketByDay[hoveredActivityDay]
                        let week = dayOffset / 7
                        let squareX = blockX + labelWidth + labelGap
                            + CGFloat(week - firstVisibleWeek) * (squareSize + columnGap)
                            + squareSize / 2
                        let row = dayOffset % 7
                        let squareY = headerHeight + CGFloat(row) * (squareSize + rowGap)
                            + squareSize / 2
                        let tooltipY = row <= 2
                            ? min(gridHeight - 31, squareY + 37)
                            : max(31, squareY - 37)
                        hoverTooltip(
                            title: hoveredActivityDay.formatted(date: .abbreviated, time: .omitted),
                            sessions: bucket?.sessions ?? 0,
                            words: bucket?.words ?? 0,
                            duration: bucket?.durationSeconds ?? 0,
                            width: 190
                        )
                        .position(
                            x: clampedTooltipX(squareX, width: 190, in: geometry.size.width),
                            y: tooltipY
                        )
                        .allowsHitTesting(false)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            }
            .frame(height: gridHeight)

            HStack(spacing: 4) {
                Spacer()
                Text("Less")
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(heatmapColor(for: [0, 1, 2, 4, 7][level]))
                        .frame(width: 12, height: 12)
                }
                Text("More")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func heatmapWeek(
        _ week: Int,
        firstVisibleWeek: Int,
        firstWeek: Date,
        firstDay: Date,
        lastDay: Date,
        buckets: [Date: DayBucket],
        calendar: Calendar,
        squareSize: CGFloat,
        rowGap: CGFloat,
        headerHeight: CGFloat
    ) -> some View {
        let days = (0..<7).compactMap { day in
            calendar.date(byAdding: .day, value: week * 7 + day, to: firstWeek)
        }
        let monthStart = days.first(where: {
            $0 >= firstDay && $0 <= lastDay && calendar.component(.day, from: $0) == 1
        })
            ?? (week == firstVisibleWeek ? days.first(where: { $0 >= firstDay }) : nil)

        return VStack(spacing: rowGap) {
            Text(monthStart?.formatted(.dateTime.month(.abbreviated)) ?? " ")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: squareSize, height: headerHeight, alignment: .leading)

            ForEach(days, id: \.self) { day in
                if day >= firstDay && day <= lastDay {
                    let sessions = buckets[day]?.sessions ?? 0
                    RoundedRectangle(cornerRadius: 2)
                        .fill(heatmapColor(for: sessions))
                        .frame(width: squareSize, height: squareSize)
                        .contentShape(Rectangle())
                        .onHover { inside in
                            hoveredActivityDay = inside ? day : nil
                        }
                        .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(sessions) \(sessions == 1 ? "session" : "sessions")")
                } else {
                    Color.clear.frame(width: squareSize, height: squareSize)
                }
            }
        }
    }

    private func heatmapColor(for sessions: Int) -> Color {
        switch sessions {
        case 0: return .gray.opacity(0.2)
        case 1: return .green.opacity(0.35)
        case 2...3: return .green.opacity(0.55)
        case 4...6: return .green.opacity(0.75)
        default: return .green
        }
    }

    private var dayChart: some View {
        let buckets = analytics.dayBuckets(range: range)
        return Chart(buckets) { bucket in
            BarMark(
                x: .value("Day", bucket.day, unit: .day),
                y: .value("Sessions", bucket.sessions)
            )
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                if range == .last7Days {
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartYScale(domain: .automatic(includesZero: true))
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let point):
                                hoveredDay = hoveredBar(
                                    at: point,
                                    in: geometry,
                                    proxy: proxy,
                                    buckets: buckets,
                                    x: { $0.day },
                                    value: { Double($0.sessions) }
                                )?.day
                            case .ended:
                                hoveredDay = nil
                            }
                        }

                    if let bucket = buckets.first(where: { $0.day == hoveredDay }),
                       let plotFrame = proxy.plotFrame,
                       let x = proxy.position(forX: bucket.day),
                       let y = proxy.position(forY: Double(bucket.sessions)) {
                        let plot = geometry[plotFrame]
                        hoverTooltip(
                            title: bucket.day.formatted(date: .abbreviated, time: .omitted),
                            sessions: bucket.sessions,
                            words: bucket.words,
                            duration: bucket.durationSeconds,
                            width: 190
                        )
                        .position(
                            x: clampedTooltipX(plot.minX + x, width: 190, in: geometry.size.width),
                            y: max(34, plot.minY + y - 36)
                        )
                        .allowsHitTesting(false)
                    }
                }
            }
        }
        .overlay {
            if buckets.allSatisfy({ $0.sessions == 0 }) {
                emptyOverlay
            }
        }
    }

    private var hourChart: some View {
        let buckets = analytics.hourBuckets(range: range)
        return Chart(buckets) { bucket in
            BarMark(
                x: .value("Hour", bucket.hour),
                y: .value("Minutes", bucket.durationSeconds / 60)
            )
        }
        .chartXScale(domain: 0...23)
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let hour = value.as(Int.self) {
                        Text(hourLabel(hour))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartYScale(domain: .automatic(includesZero: true))
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let point):
                                hoveredHour = hoveredBar(
                                    at: point,
                                    in: geometry,
                                    proxy: proxy,
                                    buckets: buckets,
                                    x: { $0.hour },
                                    value: { $0.durationSeconds / 60 }
                                )?.hour
                            case .ended:
                                hoveredHour = nil
                            }
                        }

                    if let bucket = buckets.first(where: { $0.hour == hoveredHour }),
                       let plotFrame = proxy.plotFrame,
                       let x = proxy.position(forX: bucket.hour),
                       let y = proxy.position(forY: bucket.durationSeconds / 60) {
                        let plot = geometry[plotFrame]
                        hoverTooltip(
                            title: bucket.label,
                            sessions: bucket.sessions,
                            words: bucket.words,
                            duration: bucket.durationSeconds,
                            width: 190
                        )
                        .position(
                            x: clampedTooltipX(plot.minX + x, width: 190, in: geometry.size.width),
                            y: max(34, plot.minY + y - 36)
                        )
                        .allowsHitTesting(false)
                    }
                }
            }
        }
        .overlay {
            if buckets.allSatisfy({ $0.durationSeconds == 0 && $0.sessions == 0 }) {
                emptyOverlay
            }
        }
    }

    private func hoverTooltip(
        title: String,
        sessions: Int,
        words: Int,
        duration: Double,
        width: CGFloat
    ) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
            Text("\(sessions) \(sessions == 1 ? "session" : "sessions") · \(Self.formatDuration(duration))")
                .font(.caption2)
            Text("\(words.formatted()) \(words == 1 ? "word" : "words")")
                .font(.caption2)
        }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: width)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    private func clampedTooltipX(_ x: CGFloat, width: CGFloat, in chartWidth: CGFloat) -> CGFloat {
        min(max(x, width / 2), chartWidth - width / 2)
    }

    private func hoveredBar<Bucket, X: Plottable>(
        at point: CGPoint,
        in geometry: GeometryProxy,
        proxy: ChartProxy,
        buckets: [Bucket],
        x: (Bucket) -> X,
        value: (Bucket) -> Double
    ) -> Bucket? {
        guard let plotFrame = proxy.plotFrame else { return nil }
        let plot = geometry[plotFrame]
        let localX = point.x - plot.minX
        let localY = point.y - plot.minY
        guard localX >= 0, localX <= plot.width, localY >= 0, localY <= plot.height else { return nil }

        let positions = buckets.compactMap { bucket -> (Bucket, CGFloat)? in
            guard let position = proxy.position(forX: x(bucket)) else { return nil }
            return (bucket, position)
        }
        guard let nearest = positions.min(by: { abs($0.1 - localX) < abs($1.1 - localX) }) else { return nil }
        let barWidth = plot.width / CGFloat(max(buckets.count, 1))
        guard abs(nearest.1 - localX) <= barWidth / 2, value(nearest.0) > 0,
              let top = proxy.position(forY: value(nearest.0)),
              let bottom = proxy.position(forY: 0.0),
              localY >= top, localY <= bottom else { return nil }
        return nearest.0
    }

    private var emptyOverlay: some View {
        Text("No dictation yet in this range")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("j")
        return formatter.string(from: date)
    }

    static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        }
        if minutes > 0 {
            return String(format: "%dm %ds", minutes, secs)
        }
        return String(format: "%ds", secs)
    }
}

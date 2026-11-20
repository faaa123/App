import Charts
import StudyCore
import SwiftUI

/// Weekly / monthly planned study time and the streak.
struct StatsView: View {
    @Environment(StudyController.self) private var study

    @State private var width: CGFloat = 0

    var body: some View {
        let byDate = study.minutesByDate()
        let today = study.today
        let threshold = Binding(get: { study.threshold }, set: { study.setThreshold($0) })
        let week = Self.lastDays(7, today: today, byDate: byDate)
        let month = Self.lastDays(30, today: today, byDate: byDate)
        // Side by side charts on a landscape (or large) iPad.
        let wide = width >= 960
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // The three tiles in a row, stacked when they don't fit.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        tiles(week: week, threshold: threshold)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 16) {
                        tiles(week: week, threshold: threshold)
                    }
                }
                if wide {
                    HStack(alignment: .top, spacing: 20) {
                        PeriodCard(title: "直近7日", days: week, threshold: threshold.wrappedValue, showsValues: true)
                        PeriodCard(title: "直近30日", days: month, threshold: threshold.wrappedValue, showsValues: false)
                    }
                } else {
                    PeriodCard(title: "直近7日", days: week, threshold: threshold.wrappedValue, showsValues: true)
                    PeriodCard(title: "直近30日", days: month, threshold: threshold.wrappedValue, showsValues: false)
                }
                Text("スケジュールに入っている勉強時間（予定）を集計しています。今日の分は、今のスケジュールから計算した見込みです。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(20)
        }
        .readableWidth(1280)
        .background(Color(.systemGroupedBackground))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .navigationTitle("統計")
    }

    @ViewBuilder
    private func tiles(week: [DayMinutes], threshold: Binding<Int>) -> some View {
        let total = week.reduce(0) { $0 + $1.minutes }
        StreakTile(streak: study.streak())
        Card {
            VStack(alignment: .leading, spacing: 8) {
                MinuteStepper(label: "達成の基準", value: threshold, range: 10...720, step: 10)
                    .font(.headline)
                Text("1日の勉強時間がこれ以上の日を「達成」として数えます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text("直近7日の合計")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(Format.minutes(total))
                    .font(.title.bold())
                    .monospacedDigit()
                Text("平均 \(Format.minutes(total / max(week.count, 1)))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .accessibilityElement(children: .combine)
    }

    /// The last n logical days, oldest first, ending today.
    static func lastDays(_ n: Int, today: CivilDate, byDate: [String: Int]) -> [DayMinutes] {
        (0..<n).reversed().map { i in
            let d = today.adding(days: -i)
            return DayMinutes(date: d, minutes: byDate[d.key] ?? 0, isToday: i == 0)
        }
    }
}

struct DayMinutes: Identifiable {
    let date: CivilDate
    let minutes: Int
    var isToday = false
    var id: String { date.key }
}

/// The streak, with the study color on the flame while it runs.
private struct StreakTile: View {
    let streak: Int
    /// Grows with Dynamic Type like the large-title style.
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 56

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "flame")
                        .symbolVariant(streak > 0 ? .fill : .none)
                        .foregroundStyle(streak > 0 ? AnyShapeStyle(BlockStyle.study.color)
                                         : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                    Text("連続達成")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline.weight(.semibold))
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(streak)")
                        .font(.system(size: numberSize, weight: .semibold))
                        .monospacedDigit()
                    Text("日").font(.title2.bold())
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("連続達成")
        .accessibilityValue("\(streak)日")
    }
}

/// Bars per day with the goal as a dashed rule. Met days are solid with a
/// check mark; missed days are grey, so the difference is in shape as well as
/// color. Today (an estimate) is paler. Swift Charts adds VoiceOver's audio
/// graph; each bar reads as "11月20日、1時間30分、達成".
private struct PeriodCard: View {
    let title: String
    let days: [DayMinutes]
    let threshold: Int
    let showsValues: Bool
    /// The day under the finger or pointer (Swift Charts selection).
    @State private var selectedKey: String?

    var body: some View {
        let total = days.reduce(0) { $0 + $1.minutes }
        let met = days.filter { $0.minutes >= threshold }.count
        Card {
            VStack(alignment: .leading, spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) { heading; Spacer(); summary(total, met) }
                    VStack(alignment: .leading, spacing: 4) { heading; summary(total, met) }
                }
                chart
                    .frame(height: 200)
                    .chartXSelection(value: $selectedKey)
            }
        }
    }

    private var heading: some View {
        Text(title).font(.title2.weight(.semibold))
    }

    private func summary(_ total: Int, _ met: Int) -> some View {
        Text("合計 \(Format.minutes(total))・平均 \(Format.minutes(total / max(days.count, 1)))・達成 \(met)日")
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    private var chart: some View {
        let mark = BlockStyle.study.mark
        return Chart {
            ForEach(days) { d in
                let ok = d.minutes >= threshold
                BarMark(
                    x: .value("日付", d.id),
                    y: .value("勉強時間", d.minutes),
                    width: .ratio(0.7)
                )
                .foregroundStyle(d.isToday ? mark.opacity(0.5) : ok ? mark : Color(.systemGray3))
                .cornerRadius(4)
                .annotation(position: .top, spacing: 4) {
                    if showsValues && d.minutes > 0 {
                        Text(Format.minutes(d.minutes))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else if ok {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(mark)
                    }
                }
                .accessibilityLabel("\(d.date.month)月\(d.date.day)日\(d.isToday ? "（今日）" : "")")
                .accessibilityValue("\(Format.minutes(d.minutes))\(ok ? "、達成" : "")")
            }
            if let key = selectedKey, let d = days.first(where: { $0.id == key }) {
                // Callout for the selected day (touch, drag or hover).
                RuleMark(x: .value("日付", key))
                    .foregroundStyle(.tertiary)
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(spacing: 2) {
                            Text("\(d.date.month)月\(d.date.day)日（\(Format.weekdayLabels[d.date.weekday])）")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(Format.minutes(d.minutes))
                                .font(.headline.monospacedDigit())
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 12, style: .continuous))
                    }
                    .accessibilityHidden(true)
            }
            RuleMark(y: .value("基準", threshold))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("基準 \(Format.minutes(threshold))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityHidden(true)
        }
        .chartXAxis {
            AxisMarks(values: xLabels) { value in
                AxisValueLabel {
                    if let key = value.as(String.self), let d = CivilDate(key: key) {
                        Text(Format.shortDate(d))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let m = value.as(Int.self) {
                        Text(m % 60 == 0 ? "\(m / 60)時間" : Format.minutes(m))
                    }
                }
            }
        }
        .chartYScale(domain: 0...max(threshold, days.map(\.minutes).max() ?? 0, 60))
    }

    /// Every day for a week; about once a week for a month (always today).
    private var xLabels: [String] {
        guard days.count > 7 else { return days.map(\.id) }
        return days.enumerated().filter { (days.count - 1 - $0.offset) % 7 == 0 }.map(\.element.id)
    }
}

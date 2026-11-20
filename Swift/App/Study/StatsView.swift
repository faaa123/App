import Charts
import StudyCore
import SwiftUI

/// Weekly / monthly planned study time and the streak.
struct StatsView: View {
    @Environment(StudyController.self) private var study

    var body: some View {
        let byDate = study.minutesByDate()
        let today = study.today
        let threshold = study.threshold
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StreakCard(streak: study.streak(), threshold: Binding(
                    get: { threshold },
                    set: { study.setThreshold($0) }
                ))
                PeriodCard(title: "直近7日", days: Self.lastDays(7, today: today, byDate: byDate),
                           threshold: threshold, showsValues: true)
                PeriodCard(title: "直近30日", days: Self.lastDays(30, today: today, byDate: byDate),
                           threshold: threshold, showsValues: false)
                Text("スケジュールに入っている勉強時間（予定）を集計しています。今日の分は、今のスケジュールから計算した見込みです。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(20)
            .readableWidth(900)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("統計")
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

private struct StreakCard: View {
    let streak: Int
    @Binding var threshold: Int

    var body: some View {
        Card {
            // Wraps the stepper below the streak in narrow windows.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) { count; Spacer(minLength: 0); stepper.frame(maxWidth: 340) }
                VStack(alignment: .leading, spacing: 16) { count; stepper }
            }
        }
    }

    private var count: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: streak > 0 ? "flame.fill" : "flame")
                .font(.system(size: 36))
                .foregroundStyle(streak > 0 ? AnyShapeStyle(Color.orange) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
            Text("\(streak)")
                .font(.system(size: 56, weight: .semibold, design: .rounded).monospacedDigit())
            Text("日連続").font(.title2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("連続達成")
        .accessibilityValue("\(streak)日")
    }

    private var stepper: some View {
        VStack(alignment: .leading, spacing: 4) {
            MinuteStepper(label: "達成の基準", value: $threshold, range: 10...720, step: 10)
            Text("1日の勉強時間がこれ以上の日を「達成」として数えます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// Bars per day with the goal as a dashed rule. Met days are solid with a
/// check mark; missed days are pale, so the difference is in shape as well as
/// color. Swift Charts adds VoiceOver's audio graph; each bar reads as
/// "11月20日、1時間30分、達成".
private struct PeriodCard: View {
    let title: String
    let days: [DayMinutes]
    let threshold: Int
    let showsValues: Bool

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
                .foregroundStyle(ok ? mark : mark.opacity(0.35))
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

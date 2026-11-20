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
                Text("スケジュール上の勉強時間（予定ベース）です。今日の値は暫定です。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                StreakCard(streak: study.streak(), threshold: Binding(
                    get: { threshold },
                    set: { study.setThreshold($0) }
                ))
                PeriodCard(title: "直近7日", days: Self.lastDays(7, today: today, byDate: byDate), threshold: threshold)
                PeriodCard(title: "直近30日", days: Self.lastDays(30, today: today, byDate: byDate), threshold: threshold)
            }
            .padding(24)
            .readableWidth(900)
        }
        .navigationTitle("統計")
    }

    /// The last n logical days, oldest first, ending today.
    static func lastDays(_ n: Int, today: CivilDate, byDate: [String: Int]) -> [DayMinutes] {
        (0..<n).reversed().map { i in
            let d = today.adding(days: -i)
            return DayMinutes(date: d, minutes: byDate[d.key] ?? 0)
        }
    }
}

struct DayMinutes: Identifiable {
    let date: CivilDate
    let minutes: Int
    var id: String { date.key }
}

private struct StreakCard: View {
    let streak: Int
    @Binding var threshold: Int

    var body: some View {
        // Wraps the stepper below the streak in narrow windows.
        ViewThatFits(in: .horizontal) {
            HStack { count; Spacer(minLength: 24); stepper.frame(maxWidth: 360) }
            VStack(alignment: .leading, spacing: 12) { count; stepper }
        }
        .padding(24)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private var count: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("\(streak)")
                .font(.system(size: 56, weight: .semibold).monospacedDigit())
            Text("日連続").font(.title2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(streak)日連続")
    }

    private var stepper: some View {
        MinuteStepper(label: "達成の基準（1日）", value: $threshold, range: 10...720, step: 10)
    }
}

private struct PeriodCard: View {
    let title: String
    let days: [DayMinutes]
    let threshold: Int

    var body: some View {
        let total = days.reduce(0) { $0 + $1.minutes }
        let peak = max(threshold, days.map(\.minutes).max() ?? 0)
        let showLabels = days.count <= 7
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { heading; Spacer(); summary(total) }
                VStack(alignment: .leading, spacing: 4) { heading; summary(total) }
            }
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(days) { d in
                    Bar(day: d, peak: peak, threshold: threshold, showLabels: showLabels)
                }
            }
            .frame(height: showLabels ? 170 : 140)
        }
        .padding(24)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private var heading: some View { Text(title).font(.title2.weight(.semibold)) }

    private func summary(_ total: Int) -> some View {
        Text("合計 \(Format.minutes(total))　平均 \(Format.minutes(total / max(days.count, 1)))")
    }
}

/// One day's column. Missed days are outlined (same hue), so they differ by
/// shape as well as by color. VoiceOver reads one item per day.
private struct Bar: View {
    let day: DayMinutes
    let peak: Int
    let threshold: Int
    let showLabels: Bool

    var body: some View {
        let met = day.minutes >= threshold
        let mark = BlockStyle.study.mark
        VStack(spacing: 4) {
            if showLabels && day.minutes > 0 {
                Text(Format.minutes(day.minutes))
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            GeometryReader { geo in
                let h = max(2, geo.size.height * CGFloat(day.minutes) / CGFloat(max(peak, 1)))
                VStack {
                    Spacer(minLength: 0)
                    UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4)
                        .fill(met ? mark : mark.opacity(0.3))
                        .overlay {
                            if !met {
                                UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4)
                                    .stroke(mark, lineWidth: 1)
                            }
                        }
                        .frame(height: h)
                }
            }
            if showLabels {
                Text(Format.shortDate(day.date))
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(day.date.month)月\(day.date.day)日 \(Format.minutes(day.minutes))\(met ? "、達成" : "")")
    }
}

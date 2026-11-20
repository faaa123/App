import StudyCore
import SwiftUI

/// The app's main screen: what to do now and how long is left.
struct NowView: View {
    @Environment(StudyController.self) private var study
    @Environment(\.verticalSizeClass) private var vSize

    var body: some View {
        // Ticks just after each wall-clock second, so the countdown changes in
        // step with the clock (and the chimes). Only this screen ticks.
        TimelineView(.periodic(from: Self.alignedStart, by: 1)) { _ in
            content(at: study.now())
        }
        .navigationTitle(Format.date(study.today))
        .navigationBarTitleDisplayMode(.inline)
    }

    private static var alignedStart: Date {
        Date(timeIntervalSince1970: (Date().timeIntervalSince1970).rounded(.down) + 0.005)
    }

    @ViewBuilder
    private func content(at now: Instant) -> some View {
        let blocks = study.blocks
        let status = resolveNow(blocks, now: now.local, tomorrow: study.scheduleFor(study.today.adding(days: 1)))
        let offset = LogicalDay.offset(of: now.local)
        GeometryReader { geo in
            let compact = geo.size.height < 600
            VStack(spacing: compact ? 12 : 24) {
                if !blocks.isEmpty {
                    Text("勉強 \(Format.minutes(elapsedStudyMinutes(blocks, offset: offset))) / \(Format.minutes(totalStudyMinutes(blocks)))")
                        .font(.title3.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .accessibilityLabel("本日の勉強時間 \(Format.minutes(totalStudyMinutes(blocks)))のうち\(Format.minutes(elapsedStudyMinutes(blocks, offset: offset)))")
                }
                StatusPanel(status: status, hasToday: !blocks.isEmpty, compact: compact)
                    .frame(maxHeight: .infinity)
                if !blocks.isEmpty {
                    DayBand(blocks: blocks, nowOffset: offset)
                }
            }
            .padding(.horizontal, compact ? 20 : 32)
            .padding(.top, compact ? 4 : 8)
            .padding(.bottom, compact ? 8 : 24)
        }
    }
}

private struct StatusPanel: View {
    let status: NowStatus
    let hasToday: Bool
    let compact: Bool

    var body: some View {
        switch status {
        case .inBlock(let s):
            let style = BlockStyle.of(s.block.type)
            Panel(
                color: style.color, onColor: style.onColor, icon: style.icon,
                title: Format.titled(s.block),
                seconds: s.remainingSeconds,
                caption: "〜\(LogicalDay.clock(s.block.end))",
                progress: s.progress,
                footer: footer(s),
                compact: compact)
        case .free(let next, let secs):
            Panel(icon: "hourglass", title: "フリー", seconds: secs,
                  caption: "「\(next.name)」が始まるまで", compact: compact)
        case .dayEnded(.none):
            Panel(icon: "calendar.badge.plus", title: "スケジュールがありません",
                  caption: "「スケジュール」から勉強・休憩のブロックを作りましょう", compact: compact)
        case .dayEnded(.some(let secs)):
            Panel(icon: "moon.zzz", title: hasToday ? "本日の予定は終了" : "本日は予定なし",
                  seconds: secs, caption: "明日の最初のブロックまで", compact: compact)
        }
    }

    private func footer(_ s: NowStatus.InBlock) -> String {
        guard let next = s.next, let until = s.secondsUntilNext else { return "本日最後のブロックです" }
        let when = until <= s.remainingSeconds ? "このあとすぐ" : "あと\(Format.until(until))"
        return "次：\(Format.nameWithType(next))・\(when)"
    }
}

/// Big status card on Liquid Glass. The countdown is the hero. Block colors
/// stay strong (they carry meaning); neutral states are clear glass.
private struct Panel: View {
    var color: Color? = nil
    var onColor: Color = .primary
    let icon: String
    let title: String
    var seconds: Int? = nil
    var caption: String? = nil
    var progress: Double? = nil
    var footer: String? = nil
    let compact: Bool

    var body: some View {
        VStack(spacing: compact ? 6 : 12) {
            Label {
                Text(title).lineLimit(1)
            } icon: {
                Image(systemName: icon)
            }
            .font(.largeTitle.weight(.semibold))
            .labelStyle(.titleAndIcon)

            if let seconds {
                // Gives up size first in short windows or with large text.
                Text(Format.countdown(seconds))
                    .font(.system(size: 300, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.05)
                    .frame(maxHeight: .infinity)
                    .layoutPriority(-1)
                    .accessibilityLabel("あと\(Format.until(seconds))")
                    .contentTransition(.numericText(countsDown: true))
            }
            if let caption {
                Text(caption)
                    .font(.title2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            if let progress {
                ProgressView(value: progress)
                    .tint(onColor)
                    .scaleEffect(x: 1, y: 3)
                    .padding(.vertical, compact ? 4 : 12)
                    .accessibilityLabel("進み具合")
                    .accessibilityValue("\(Int(progress * 100))%")
            }
            if let footer {
                Text(footer)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .foregroundStyle(onColor)
        .padding(compact ? 20 : 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(color.map { Glass.regular.tint($0.opacity(0.85)) } ?? .regular,
                     in: .rect(cornerRadius: 36))
        .accessibilityElement(children: .combine)
    }
}

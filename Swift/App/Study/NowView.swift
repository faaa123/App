import StudyCore
import SwiftUI

/// The app's main screen: what to do now and how long is left.
struct NowView: View {
    @Environment(StudyController.self) private var study

    var body: some View {
        // Ticks just after each wall-clock second, so the countdown changes in
        // step with the clock (and the chimes). Only this screen ticks.
        TimelineView(.periodic(from: Self.alignedStart, by: 1)) { _ in
            NowContent(now: study.now())
        }
        .navigationTitle(Format.date(study.today))
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private static var alignedStart: Date {
        Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down) + 0.005)
    }
}

private struct NowContent: View {
    let now: Instant
    @Environment(StudyController.self) private var study
    @Environment(AppRouter.self) private var router

    var body: some View {
        let blocks = study.blocks
        let tomorrow = study.scheduleFor(study.today.adding(days: 1))
        let status = resolveNow(blocks, now: now.local, tomorrow: tomorrow)
        let offset = LogicalDay.offset(of: now.local)
        if case .dayEnded(.none) = status {
            // Nothing scheduled today or tomorrow: say why, and where to start.
            ContentUnavailableView {
                Label("スケジュールがありません", systemImage: "calendar.badge.plus")
            } description: {
                Text("勉強と休憩のブロックを作ると、ここに残り時間が大きく表示され、切り替わりでチャイムが鳴ります。")
            } actions: {
                Button("スケジュールを作る") { router.tab = .schedule }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            GeometryReader { geo in
                let compact = geo.size.height < 600
                VStack(spacing: compact ? 12 : 20) {
                    if !blocks.isEmpty {
                        TodayTotals(blocks: blocks, offset: offset)
                    }
                    StatusPanel(status: status, hasToday: !blocks.isEmpty, compact: compact)
                        .frame(maxHeight: .infinity)
                    if !blocks.isEmpty {
                        DayBand(blocks: blocks, nowOffset: offset)
                            .padding(.horizontal, 4)
                    }
                    ChimePermissionNotice()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, compact ? 16 : 32)
                .padding(.top, compact ? 4 : 12)
                .padding(.bottom, compact ? 8 : 24)
            }
        }
    }
}

/// "今日の勉強 1時間20分 / 3時間".
private struct TodayTotals: View {
    let blocks: [Block]
    let offset: Int

    var body: some View {
        let done = elapsedStudyMinutes(blocks, offset: offset)
        let total = totalStudyMinutes(blocks)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: BlockStyle.study.icon)
                .foregroundStyle(BlockStyle.study.mark)
            Text("今日の勉強")
                .foregroundStyle(.secondary)
            Text("\(Format.minutes(done)) / \(Format.minutes(total))")
                .monospacedDigit()
                .fontWeight(.semibold)
        }
        .font(.title3)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日の勉強時間")
        .accessibilityValue("\(Format.minutes(total))のうち\(Format.minutes(done))")
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
                fill: style.color, onColor: style.onColor, icon: style.icon,
                title: Format.titled(s.block),
                seconds: s.remainingSeconds,
                caption: "〜\(LogicalDay.clock(s.block.end))",
                progress: s.progress,
                footer: footer(s),
                compact: compact)
        case .free(let next, let secs):
            Panel(icon: "hourglass", title: "フリー", seconds: secs,
                  caption: "「\(next.name)」が始まるまで", compact: compact)
        case .dayEnded(let secs):
            Panel(icon: "moon.zzz.fill", title: hasToday ? "今日の予定は終了" : "今日は予定なし",
                  seconds: secs, caption: "明日の最初のブロックまで", compact: compact)
        }
    }

    private func footer(_ s: NowStatus.InBlock) -> String {
        guard let next = s.next, let until = s.secondsUntilNext else { return "今日最後のブロックです" }
        let when = until <= s.remainingSeconds ? "このあとすぐ" : "あと\(Format.until(until))"
        return "次：\(Format.nameWithType(next))・\(when)"
    }
}

/// The big status card (content layer: a solid fill, not glass). The
/// countdown is the hero; block colors stay strong because they carry
/// meaning, and the icon repeats it for anyone who can't tell them apart.
private struct Panel: View {
    var fill: Color? = nil
    var onColor: Color = .primary
    let icon: String
    let title: String
    var seconds: Int? = nil
    var caption: String? = nil
    var progress: Double? = nil
    var footer: String? = nil
    let compact: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: compact ? 6 : 14) {
            Label {
                Text(title).lineLimit(1)
            } icon: {
                Image(systemName: icon)
            }
            .font(.largeTitle.weight(.semibold))

            if let seconds {
                // Gives up size first in short windows or with large text.
                Text(Format.countdown(seconds))
                    .font(.system(size: 280, weight: .semibold, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.05)
                    .frame(maxHeight: .infinity)
                    .layoutPriority(-1)
                    .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
                    .accessibilityLabel("残り")
                    .accessibilityValue(Format.until(seconds))
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if let caption {
                Text(caption)
                    .font(.title2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            if let progress {
                ProgressBar(value: progress, color: onColor)
                    .frame(height: compact ? 8 : 12)
                    .padding(.vertical, compact ? 2 : 8)
                    .accessibilityElement()
                    .accessibilityLabel("進み具合")
                    .accessibilityValue("\(Int((progress * 100).rounded()))%")
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
        .background(fill ?? Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 36))
        .accessibilityElement(children: .contain)
    }
}

/// A rounded track with a fill; draws the same at any height.
private struct ProgressBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.25))
                Capsule().fill(color)
                    .frame(width: max(geo.size.height, geo.size.width * min(max(value, 0), 1)))
            }
        }
    }
}

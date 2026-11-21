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
        .background(Color(.systemGroupedBackground))
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
                // The day's timetable sits beside the countdown when there is
                // room (landscape, or a large iPad); otherwise the band below.
                let wide = geo.size.width >= 960 && !blocks.isEmpty
                let gap: CGFloat = compact ? 16 : 20
                HStack(alignment: .top, spacing: gap) {
                    VStack(spacing: gap) {
                        StatusPanel(status: status, hasToday: !blocks.isEmpty, compact: compact)
                            .frame(maxHeight: .infinity)
                        if !blocks.isEmpty {
                            HStack(alignment: .top, spacing: gap) {
                                NextCard(status: status)
                                TodayCard(blocks: blocks, offset: offset)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            if !wide {
                                DayBand(blocks: blocks, nowOffset: offset)
                                    .padding(.horizontal, 4)
                            }
                        }
                        ChimePermissionNotice()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if wide {
                        TodayTimetable(blocks: blocks, offset: offset)
                            .frame(width: 340)
                    }
                }
                .padding(.horizontal, compact ? 16 : 20)
                .padding(.top, compact ? 4 : 12)
                .padding(.bottom, compact ? 12 : 24)
            }
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
                fill: style.color, onColor: style.onColor, icon: style.icon,
                kicker: "\(style.label)中",
                title: s.block.name,
                seconds: s.remainingSeconds,
                progress: s.progress,
                startLabel: "\(LogicalDay.clock(s.block.start)) 開始",
                endLabel: "\(LogicalDay.clock(s.block.end)) まで",
                compact: compact)
        case .free(let next, let secs):
            Panel(icon: "hourglass", kicker: "フリー", title: "「\(next.name)」まで",
                  seconds: secs, endLabel: "\(LogicalDay.clock(next.start)) から", compact: compact)
        case .dayEnded(let secs):
            Panel(icon: "moon.zzz.fill", kicker: hasToday ? "今日の予定は終了" : "今日は予定なし",
                  title: "明日の最初のブロックまで", seconds: secs, compact: compact)
        }
    }
}

/// The big status card (content layer: a solid fill, not glass). The
/// countdown is the hero; block colors carry meaning, and the icon and label
/// repeat it for anyone who can't tell them apart. Secondary text uses the
/// hierarchical styles, so it is derived from `onColor`.
private struct Panel: View {
    var fill: Color = Color(.secondarySystemGroupedBackground)
    var onColor: Color = .primary
    let icon: String
    let kicker: String
    let title: String
    var seconds: Int? = nil
    var progress: Double? = nil
    var startLabel: String? = nil
    var endLabel: String? = nil
    let compact: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The countdown's preferred size, scaled with Dynamic Type; it still
    /// shrinks to fit the card.
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(kicker)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.largeTitle.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                Image(systemName: icon)
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            if let seconds {
                // Gives up size first in short windows or with large text.
                Text(Format.countdown(seconds))
                    .font(.system(size: countdownSize, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.05)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .layoutPriority(-1)
                    .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
                    .accessibilityLabel("残り")
                    .accessibilityValue(Format.until(seconds))
                    .accessibilityAddTraits(.updatesFrequently)
            } else {
                Spacer(minLength: 0)
            }

            if let progress {
                SegmentedProgress(value: progress)
                    .frame(height: 8)
                    .accessibilityElement()
                    .accessibilityLabel("進み具合")
                    .accessibilityValue("\(Int((progress * 100).rounded()))%")
            }
            if startLabel != nil || endLabel != nil {
                HStack {
                    if let startLabel {
                        Text(startLabel).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 16)
                    if let endLabel {
                        Text(endLabel).fontWeight(.semibold)
                    }
                }
                .font(.title3)
                .monospacedDigit()
            }
        }
        .foregroundStyle(onColor)
        .padding(compact ? 20 : 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(fill, in: .rect(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// Ten segments that fill one after another (the last partly), in the
/// current foreground style over its quaternary track.
private struct SegmentedProgress: View {
    let value: Double

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<10, id: \.self) { i in
                let part = min(max(value * 10 - Double(i), 0), 1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill(.primary)
                            .frame(width: geo.size.width * part)
                    }
                }
            }
        }
    }
}

/// What comes after the current block (or the free time).
private struct NextCard: View {
    let status: NowStatus

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text("次")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let n = next {
                    HStack(spacing: 8) {
                        BlockMark(type: n.block.type, height: 18)
                        Text("\(Format.titled(n.block)) \(Format.minutes(n.block.duration))")
                            .font(.title3.weight(.semibold))
                            .lineLimit(1)
                    }
                    Text("あと\(Format.until(n.seconds))・\(LogicalDay.clock(n.block.start)) から")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    Text("今日最後のブロックです")
                        .font(.title3.weight(.semibold))
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .accessibilityElement(children: .combine)
    }

    private var next: (block: Block, seconds: Int)? {
        switch status {
        case .inBlock(let s):
            guard let n = s.next, let until = s.secondsUntilNext else { return nil }
            return (n, until)
        case .free(let n, let until):
            return (n, until)
        case .dayEnded:
            return nil
        }
    }
}

/// "今日の勉強 3時間52分 / 6時間20分" with a bar.
private struct TodayCard: View {
    let blocks: [Block]
    let offset: Int

    var body: some View {
        let done = elapsedStudyMinutes(blocks, offset: offset)
        let total = totalStudyMinutes(blocks)
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("今日の勉強")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Format.minutes(done))
                        .font(.title3.weight(.semibold))
                    Text("/ \(Format.minutes(total))")
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()
                ProgressView(value: total > 0 ? Double(done) / Double(total) : 0)
                    .tint(BlockStyle.study.color)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日の勉強時間")
        .accessibilityValue("\(Format.minutes(total))のうち\(Format.minutes(done))")
    }
}

/// Today's blocks as a list beside the countdown, the current one filled
/// with its block color; free time between blocks shows as a dashed row.
private struct TodayTimetable: View {
    let blocks: [Block]
    let offset: Int
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("今日")
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("編集") { router.tab = .schedule }
            }
            .padding(.horizontal, 8)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(items) { item in
                            switch item {
                            case .block(let b):
                                TimetableRow(block: b, offset: offset).id(b.id)
                            case .free(let start, let minutes):
                                FreeRow(start: start, minutes: minutes)
                            }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .onAppear {
                    if let current = blocks.first(where: { $0.contains(offset) }) {
                        proxy.scrollTo(current.id, anchor: .center)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26, style: .continuous))
    }

    private enum Item: Identifiable {
        case block(Block)
        case free(start: Int, minutes: Int)

        var id: String {
            switch self {
            case .block(let b): b.id
            case .free(let start, _): "free-\(start)"
            }
        }
    }

    private var items: [Item] {
        var out: [Item] = []
        for (i, b) in blocks.enumerated() {
            if i > 0, b.start > blocks[i - 1].end {
                out.append(.free(start: blocks[i - 1].end, minutes: b.start - blocks[i - 1].end))
            }
            out.append(.block(b))
        }
        return out
    }
}

private struct TimetableRow: View {
    let block: Block
    let offset: Int

    var body: some View {
        let style = BlockStyle.of(block.type)
        let current = block.contains(offset)
        let past = block.end <= offset
        HStack(spacing: 12) {
            Text(LogicalDay.clock(block.start))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
            BlockMark(type: block.type, height: 20)
                .opacity(past ? 0.5 : 1)
            Text(block.name)
                .fontWeight(current ? .semibold : nil)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(Format.minutes(block.duration))
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(past ? AnyShapeStyle(HierarchicalShapeStyle.secondary)
                         : AnyShapeStyle(HierarchicalShapeStyle.primary))
        .padding(.horizontal, 8)
        .frame(minHeight: 44)
        .background(current ? BlockStyle.currentRow : Color.clear, in: .rect(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(current ? "実行中、" : "")\(style.label)、\(block.name)")
        .accessibilityValue("\(LogicalDay.clock(block.start))から\(LogicalDay.clock(block.end))まで")
    }
}

private struct FreeRow: View {
    let start: Int
    let minutes: Int

    var body: some View {
        HStack(spacing: 12) {
            Text(LogicalDay.clock(start))
                .font(.subheadline.weight(.semibold))
                .frame(width: 48, alignment: .leading)
            DashedRule().frame(width: 12)
            Text("フリー")
            Spacer(minLength: 4)
            Text(Format.minutes(minutes))
                .font(.footnote)
        }
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("フリー")
        .accessibilityValue("\(LogicalDay.clock(start))から\(Format.minutes(minutes))")
    }
}

/// A horizontal dashed line for free time, in the current tertiary style.
struct DashedRule: View {
    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            p.move(to: CGPoint(x: 0, y: size.height / 2))
            p.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            ctx.stroke(p, with: .style(HierarchicalShapeStyle.tertiary),
                       style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }
}

import StudyCore
import SwiftUI

/// Edit the (single, permanent) schedule.
///
/// Every edit is undoable (⌘Z, three-finger swipe, the 取り消す button), so
/// only the rare, large "delete everything" asks for confirmation.
///
/// Wide windows show the block list beside a side panel (day total, add,
/// pomodoro, notes); narrow ones keep everything in one list.
struct ScheduleView: View {
    @Environment(StudyController.self) private var study
    @Environment(ScheduleUndo.self) private var undo
    @Environment(AppRouter.self) private var router
    @Environment(\.undoManager) private var undoManager
    @State private var editing: EditTarget?
    @State private var showPomodoro = false
    @State private var toast: ToastMessage?
    @State private var width: CGFloat = 0

    enum EditTarget: Identifiable {
        case new
        case block(Block)
        var id: String {
            switch self {
            case .new: "new"
            case .block(let b): b.id
            }
        }
    }

    var body: some View {
        let blocks = study.blocks
        let wide = width >= 960
        HStack(alignment: .top, spacing: 20) {
            blockList(blocks, wide: wide)
            if wide {
                SchedulePanel(
                    blocks: blocks,
                    onAdd: { editing = .new },
                    onPomodoro: { showPomodoro = true },
                    onDeleteAll: deleteAll)
                    .frame(width: 340)
                    .padding(.top, 20)
                    .padding(.trailing, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .navigationTitle("スケジュール")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("プリセット") { PresetsView() }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItemGroup(placement: .topBarTrailing) {
                EditButton()
                    .disabled(blocks.isEmpty)
                Button("ブロックを追加", systemImage: "plus") { editing = .new }
            }
        }
        .sheet(item: $editing) { target in
            switch target {
            case .new: BlockEditor(editing: nil)
            case .block(let b): BlockEditor(editing: b)
            }
        }
        .sheet(isPresented: $showPomodoro) { PomodoroSheet() }
        .onChange(of: router.addBlockPending, initial: true) {
            guard router.addBlockPending else { return }
            router.addBlockPending = false
            if editing == nil && !showPomodoro { editing = .new }
        }
        .toast($toast)
    }

    @ViewBuilder
    private func blockList(_ blocks: [Block], wide: Bool) -> some View {
        let list = List {
            if !wide {
                Section {
                    ScheduleSummary(showsTotal: true)
                }
            }
            Section {
                if blocks.isEmpty {
                    Text("ブロックがありません（終日フリー）")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                } else {
                    let nowOffset = LogicalDay.offset(of: study.now().local)
                    ForEach(Array(blocks.enumerated()), id: \.element.id) { i, b in
                        let current = b.contains(nowOffset)
                        // A real button: works with VoiceOver, Full Keyboard
                        // Access and pointer hover, not only touch.
                        Button { editing = .block(b) } label: {
                            BlockRow(block: b,
                                     gapBefore: i > 0 ? b.start - blocks[i - 1].end : 0,
                                     isCurrent: current,
                                     isPast: b.end <= nowOffset)
                        }
                        .tint(.primary)
                        .listRowBackground(current ? BlockStyle.of(b.type).color : nil)
                        .accessibilityHint("編集します")
                        .accessibilityAction(named: "前へ移動") { move(from: i, to: i - 1) }
                        .accessibilityAction(named: "後ろへ移動") { move(from: i, to: i + 2) }
                        .accessibilityAction(named: "削除") { delete(b) }
                        .swipeActions {
                            Button("削除", systemImage: "trash", role: .destructive) { delete(b) }
                        }
                        .contextMenu {
                            Button("編集", systemImage: "pencil") { editing = .block(b) }
                            Button("削除", systemImage: "trash", role: .destructive) { delete(b) }
                        }
                    }
                    .onMove { from, to in
                        guard let i = from.first else { return }
                        move(from: i, to: to)
                    }
                    .onDelete { offsets in
                        for i in offsets { delete(blocks[i]) }
                    }
                }
            } header: {
                if !blocks.isEmpty {
                    Text("長押ししてドラッグで並び替え（時刻は自動で詰めます）")
                        .textCase(nil)
                }
            }
            if !wide {
                Section {
                    Button("ブロックを追加", systemImage: "plus") { editing = .new }
                    Button("ポモドーロで敷き詰める…", systemImage: "timer") { showPomodoro = true }
                }
                if !blocks.isEmpty {
                    Section {
                        DeleteAllButton(count: blocks.count, onConfirm: deleteAll)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        if wide {
            list
        } else {
            list.readableWidth()
        }
    }

    private func perform(_ name: String, _ change: () -> Void) {
        undo.perform(name, undoManager: undoManager, change)
    }

    /// Reorders by list position (`to` as in `onMove`: the index before which
    /// the block lands). Gaps stay where they are.
    private func move(from: Int, to: Int) {
        var ids = study.blocks.map(\.id)
        guard ids.indices.contains(from), (0...ids.count).contains(to), to != from, to != from + 1 else { return }
        ids.move(fromOffsets: IndexSet(integer: from), toOffset: to)
        var error: String?
        perform("並び替え") { error = study.reorder(ids) }
        if let error { toast = ToastMessage(text: error) }
    }

    private func delete(_ removed: Block) {
        perform("ブロックを削除") { study.deleteBlock(id: removed.id) }
        toast = ToastMessage(text: "「\(removed.name)」を削除しました", actionLabel: "取り消す") { undo.undo() }
    }

    private func deleteAll() {
        perform("すべて削除") { study.deleteAll() }
        toast = ToastMessage(text: "すべてのブロックを削除しました", actionLabel: "取り消す") { undo.undo() }
    }
}

/// The destructive "delete everything" button with its confirmation.
private struct DeleteAllButton: View {
    let count: Int
    let onConfirm: () -> Void
    @State private var confirming = false

    var body: some View {
        Button("すべてのブロックを削除…", systemImage: "trash", role: .destructive) {
            confirming = true
        }
        .confirmationDialog("すべてのブロックを削除しますか？", isPresented: $confirming,
                            titleVisibility: .visible) {
            Button("\(count)個のブロックを削除", role: .destructive, action: onConfirm)
        } message: {
            Text("あとから「取り消す」で元に戻せます。")
        }
    }
}

/// The side panel of the wide layout: the day's total, the main actions, and
/// the notes.
private struct SchedulePanel: View {
    let blocks: [Block]
    let onAdd: () -> Void
    let onPomodoro: () -> Void
    let onDeleteAll: () -> Void
    @Environment(StudyController.self) private var study

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                totalCard
                Button(action: onAdd) {
                    Label("ブロックを追加", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                Button(action: onPomodoro) {
                    Label("ポモドーロで敷き詰める", systemImage: "timer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                Card {
                    ScheduleSummary(showsTotal: false)
                }
                if !blocks.isEmpty {
                    DeleteAllButton(count: blocks.count, onConfirm: onDeleteAll)
                        .padding(.top, 8)
                }
            }
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var totalCard: some View {
        let studyCount = blocks.filter(\.isStudy).count
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("1日の勉強時間")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(Format.minutes(totalStudyMinutes(blocks)))
                    .font(.largeTitle.bold())
                    .monospacedDigit()
                if let first = blocks.first, let last = blocks.last {
                    DayBand(blocks: blocks, nowOffset: LogicalDay.offset(of: study.now().local),
                            showsLabels: false, height: 28)
                    HStack {
                        Text(LogicalDay.clock(first.start))
                        Spacer()
                        Text("勉強 \(studyCount)・休憩 \(blocks.count - studyCount)")
                        Spacer()
                        Text(LogicalDay.clock(last.end))
                    }
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Today's total, what tomorrow brings, and whether chimes can sound.
private struct ScheduleSummary: View {
    var showsTotal = true
    @Environment(StudyController.self) private var study

    var body: some View {
        let tomorrow = study.today.adding(days: 1)
        VStack(alignment: .leading, spacing: 12) {
            if showsTotal {
                LabeledContent("1日の勉強時間") {
                    Text(Format.minutes(totalStudyMinutes(study.blocks)))
                        .monospacedDigit()
                        .fontWeight(.semibold)
                }
                .font(.headline)
            }
            Label("編集は次の日以降も続きます。曜日を割り当てたプリセットがある日は、その日の4:00にプリセットに切り替わります。",
                  systemImage: "arrow.triangle.2.circlepath")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let p = study.presetForWeekday(tomorrow.weekday) {
                Label("明日（\(Format.weekdayLabels[tomorrow.weekday])曜）はプリセット「\(p.name)」に切り替わります",
                      systemImage: "calendar.badge.clock")
                    .font(.footnote)
                    .foregroundStyle(.tint)
            }
            if !study.blocks.isEmpty {
                Label("チャイムは7日先まで予約されます。1週間以上アプリを開かないと鳴らなくなります。",
                      systemImage: "bell")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ChimePermissionNotice()
        }
        .padding(.vertical, 4)
    }
}

private struct BlockRow: View {
    let block: Block
    /// Free minutes since the previous block (0 = back to back).
    var gapBefore = 0
    var isCurrent = false
    var isPast = false

    var body: some View {
        let style = BlockStyle.of(block.type)
        VStack(alignment: .leading, spacing: 8) {
            if gapBefore > 0 {
                // Free time between blocks, so the timetable reads like a day.
                HStack(spacing: 8) {
                    DashedRule().frame(width: 12)
                    Text("フリー \(Format.minutes(gapBefore))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                BlockMark(type: block.type, color: isCurrent ? style.onColor : nil,
                          height: block.isStudy ? 32 : 20)
                    .opacity(isPast ? 0.5 : 1)
                // Times lead (they are what a timetable is scanned for); the
                // name shows only when it says more than the type.
                VStack(alignment: .leading, spacing: 2) {
                    Text(rangeLabel(block))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    Text(block.name == style.label
                         ? Format.minutes(block.duration)
                         : "\(block.name)・\(Format.minutes(block.duration))")
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if isCurrent {
                    Text("いま")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .foregroundStyle(style.color)
                        .background(style.onColor, in: .capsule)
                }
            }
        }
        .foregroundStyle(isCurrent ? AnyShapeStyle(style.onColor) : AnyShapeStyle(HierarchicalShapeStyle.primary))
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(isCurrent ? "実行中、" : "")\(style.label)、\(block.name)")
        .accessibilityValue("\(LogicalDay.clock(block.start))から\(LogicalDay.clock(block.end))まで、\(Format.minutes(block.duration))\(gapBefore > 0 ? "、前にフリー\(Format.minutes(gapBefore))" : "")")
    }
}

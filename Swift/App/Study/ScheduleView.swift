import StudyCore
import SwiftUI

/// Edit the (single, permanent) schedule.
///
/// Every edit is undoable (⌘Z, three-finger swipe, the 取り消す button), so
/// only the rare, large "delete everything" asks for confirmation.
struct ScheduleView: View {
    @Environment(StudyController.self) private var study
    @Environment(ScheduleUndo.self) private var undo
    @Environment(\.undoManager) private var undoManager
    @State private var editing: EditTarget?
    @State private var showPomodoro = false
    @State private var confirmDeleteAll = false
    @State private var toast: ToastMessage?

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
        List {
            Section {
                ScheduleSummary()
            }
            Section {
                if blocks.isEmpty {
                    Text("ブロックがありません（終日フリー）")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                } else {
                    ForEach(Array(blocks.enumerated()), id: \.element.id) { i, b in
                        BlockRow(block: b)
                            .contentShape(.rect)
                            .onTapGesture { editing = .block(b) }
                            .accessibilityAddTraits(.isButton)
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
            Section {
                Button("ブロックを追加", systemImage: "plus") { editing = .new }
                Button("ポモドーロで敷き詰める…", systemImage: "timer") { showPomodoro = true }
            }
            if !blocks.isEmpty {
                Section {
                    Button("すべてのブロックを削除…", systemImage: "trash", role: .destructive) {
                        confirmDeleteAll = true
                    }
                    .confirmationDialog("すべてのブロックを削除しますか？", isPresented: $confirmDeleteAll,
                                        titleVisibility: .visible) {
                        Button("\(blocks.count)個のブロックを削除", role: .destructive) {
                            perform("すべて削除") { study.deleteAll() }
                            toast = ToastMessage(text: "すべてのブロックを削除しました", actionLabel: "取り消す") { undo.undo() }
                        }
                    } message: {
                        Text("あとから「取り消す」で元に戻せます。")
                    }
                }
            }
        }
        .readableWidth()
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
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(item: $editing) { target in
            switch target {
            case .new: BlockEditor(editing: nil)
            case .block(let b): BlockEditor(editing: b)
            }
        }
        .sheet(isPresented: $showPomodoro) { PomodoroSheet() }
        .toast($toast)
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
}

/// Today's total, what tomorrow brings, and whether chimes can sound.
private struct ScheduleSummary: View {
    @Environment(StudyController.self) private var study

    var body: some View {
        let tomorrow = study.today.adding(days: 1)
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("1日の勉強時間") {
                Text(Format.minutes(totalStudyMinutes(study.blocks)))
                    .monospacedDigit()
                    .fontWeight(.semibold)
            }
            .font(.headline)
            Text("編集は次の日以降も続きます。曜日を割り当てたプリセットがある日は、その日の4:00にプリセットに切り替わります。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let p = study.presetForWeekday(tomorrow.weekday) {
                Label("明日（\(Format.weekdayLabels[tomorrow.weekday])曜）はプリセット「\(p.name)」に切り替わります",
                      systemImage: "arrow.triangle.2.circlepath")
                    .font(.footnote)
                    .foregroundStyle(.tint)
            }
            ChimePermissionNotice()
        }
        .padding(.vertical, 4)
    }
}

private struct BlockRow: View {
    let block: Block

    var body: some View {
        let style = BlockStyle.of(block.type)
        HStack(spacing: 16) {
            Image(systemName: style.icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(style.onColor)
                .frame(width: 40, height: 40)
                .background(style.color, in: .circle)
                .accessibilityHidden(true)
            // Times lead (they are what a timetable is scanned for); the name
            // shows only when it says more than the icon's type.
            VStack(alignment: .leading, spacing: 2) {
                Text(rangeLabel(block))
                    .font(.title3.monospacedDigit())
                Text(block.name == style.label
                     ? Format.minutes(block.duration)
                     : "\(block.name)・\(Format.minutes(block.duration))")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(style.label)、\(block.name)")
        .accessibilityValue("\(LogicalDay.clock(block.start))から\(LogicalDay.clock(block.end))まで、\(Format.minutes(block.duration))")
    }
}

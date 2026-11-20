import StudyCore
import SwiftUI

/// Edit the (single, permanent) schedule.
struct ScheduleView: View {
    @Environment(StudyController.self) private var study
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
        let tomorrow = study.today.adding(days: 1)
        let tomorrowPreset = study.presetForWeekday(tomorrow.weekday)
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1日の合計勉強時間：\(Format.minutes(totalStudyMinutes(blocks)))")
                        .font(.headline)
                    Text("編集は翌日以降も引き継がれます（プリセットを割り当てた曜日は、その日の4:00にプリセットで置き換わります）。")
                    Text("長押ししてドラッグで並び替え（時刻は自動で詰めます）。")
                    if let p = tomorrowPreset {
                        Text("明日（\(Format.weekdayLabels[tomorrow.weekday])曜）はプリセット「\(p.name)」に切り替わります。")
                            .foregroundStyle(.tint)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
            }
            Section {
                if blocks.isEmpty {
                    Text("ブロックがありません（終日フリー）")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(blocks) { b in
                        BlockRow(block: b) { delete(b) }
                            .contentShape(.rect)
                            .onTapGesture { editing = .block(b) }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint("編集します")
                            .swipeActions {
                                Button("削除", systemImage: "trash", role: .destructive) { delete(b) }
                            }
                    }
                    .onMove { from, to in
                        var ids = blocks.map(\.id)
                        ids.move(fromOffsets: from, toOffset: to)
                        if let err = study.reorder(ids) { toast = ToastMessage(text: err) }
                    }
                }
            }
            Section {
                Button("ブロックを追加", systemImage: "plus") { editing = .new }
                Button("ポモドーロで敷き詰める", systemImage: "timer") { showPomodoro = true }
            }
            if !blocks.isEmpty {
                Section {
                    Button("すべてのブロックを削除", systemImage: "trash", role: .destructive) {
                        confirmDeleteAll = true
                    }
                    .confirmationDialog("すべて削除しますか？", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                        Button("削除", role: .destructive) { study.deleteAll() }
                    } message: {
                        Text("\(blocks.count)個のブロックをすべて削除します。")
                    }
                }
            }
        }
        .readableWidth()
        .navigationTitle("スケジュール")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    PresetsView()
                } label: {
                    Label("プリセット", systemImage: "bookmark")
                        .labelStyle(.titleAndIcon)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("追加", systemImage: "plus") { editing = .new }
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

    /// One-tap delete with undo (a mis-tap is otherwise permanent).
    private func delete(_ removed: Block) {
        study.deleteBlock(id: removed.id)
        toast = ToastMessage(text: "「\(removed.name)」を削除しました", actionLabel: "元に戻す") {
            // Re-validated: the slot may have been filled meanwhile.
            if let err = study.addBlock(removed) { toast = ToastMessage(text: err) }
        }
    }
}

private struct BlockRow: View {
    let block: Block
    let onDelete: () -> Void

    var body: some View {
        let style = BlockStyle.of(block.type)
        HStack(spacing: 16) {
            Image(systemName: style.icon)
                .foregroundStyle(style.onColor)
                .frame(width: 40, height: 40)
                .background(style.color, in: .circle)
                .accessibilityLabel(style.label)
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
            Button("削除", systemImage: "xmark", action: onDelete)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "削除", onDelete)
    }
}

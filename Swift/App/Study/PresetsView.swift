import StudyCore
import SwiftUI

/// Named schedules, optionally applied automatically on chosen weekdays.
/// Loading and deleting are undoable, so they don't ask first.
struct PresetsView: View {
    @Environment(StudyController.self) private var study
    @Environment(ScheduleUndo.self) private var undo
    @Environment(\.undoManager) private var undoManager
    @State private var askingName = false
    @State private var newName = ""
    @State private var toast: ToastMessage?

    var body: some View {
        List {
            Section {
                Text("曜日を選ぶと、その曜日の4:00に自動でスケジュールがこのプリセットに切り替わります。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
            }
            if study.presets.isEmpty {
                ContentUnavailableView {
                    Label("プリセットはまだありません", systemImage: "square.stack.3d.up")
                } description: {
                    Text("今のスケジュールに名前を付けて保存しておくと、いつでも読み込んだり、曜日ごとに自動で切り替えたりできます。")
                }
                .listRowBackground(Color.clear)
            }
            ForEach(study.presets) { p in
                Section {
                    PresetCard(preset: p,
                               contested: contested(p),
                               onLoad: { load(p) },
                               onDelete: { delete(p) })
                }
                .listRowBackground(Theme.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.page)
        .readableWidth()
        .navigationTitle("プリセット")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("今のスケジュールを保存", systemImage: "square.and.arrow.down") {
                    newName = ""
                    askingName = true
                }
                .labelStyle(.titleAndIcon)
                .disabled(study.blocks.isEmpty)
            }
        }
        .alert("プリセットの名前", isPresented: $askingName) {
            TextField("例：平日", text: $newName)
            Button("キャンセル", role: .cancel) {}
            Button("保存") {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                perform("プリセットを保存") { study.saveAsPreset(name: name) }
            }
        } message: {
            Text("今のスケジュール（\(study.blocks.count)ブロック）を保存します。")
        }
        .toast($toast)
    }

    /// Weekdays this preset claims but another preset wins.
    private func contested(_ p: Preset) -> [(weekday: Int, winner: Preset)] {
        study.contestedWeekdays().filter { p.weekdays.contains($0.weekday) && $0.winner.id != p.id }
    }

    private func perform(_ name: String, _ change: () -> Void) {
        undo.perform(name, undoManager: undoManager, change)
    }

    private func load(_ p: Preset) {
        perform("プリセットを読み込む") { study.applyPreset(id: p.id) }
        toast = ToastMessage(text: "「\(p.name)」を今のスケジュールにしました", actionLabel: "取り消す") { undo.undo() }
    }

    private func delete(_ p: Preset) {
        perform("プリセットを削除") { study.deletePreset(id: p.id) }
        toast = ToastMessage(text: "プリセット「\(p.name)」を削除しました", actionLabel: "取り消す") { undo.undo() }
    }
}

private struct PresetCard: View {
    let preset: Preset
    let contested: [(weekday: Int, winner: Preset)]
    let onLoad: () -> Void
    let onDelete: () -> Void
    @Environment(StudyController.self) private var study
    @Environment(ScheduleUndo.self) private var undo
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) { title; Spacer(); summary }
                VStack(alignment: .leading, spacing: 4) { title; summary }
            }
            if !preset.blocks.isEmpty {
                DayBand(blocks: preset.blocks, nowOffset: -1, showsLabels: true, height: 20,
                        accessibilityPrefix: "プリセット")
            }
            WeekdayToggles(selected: preset.weekdays) { days in
                undo.perform("曜日を変更", undoManager: undoManager) {
                    study.setPresetWeekdays(id: preset.id, days)
                }
            }
            ForEach(contested, id: \.weekday) { c in
                Label("\(Format.weekdayLabels[c.weekday])曜は、あとから設定した「\(c.winner.name)」が使われます",
                      systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("削除", systemImage: "trash", role: .destructive, action: onDelete)
                    .buttonStyle(.bordered)
                Spacer()
                Button("このプリセットを読み込む", action: onLoad)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 8)
        .contextMenu {
            Button("読み込む", systemImage: "square.and.arrow.up.on.square", action: onLoad)
            Button("削除", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private var title: some View {
        Text(preset.name).font(.title3.weight(.semibold))
    }

    private var summary: some View {
        Text("\(preset.blocks.count)ブロック・勉強\(Format.minutes(totalStudyMinutes(preset.blocks)))")
            .foregroundStyle(.secondary)
    }
}

/// 日〜土 as toggle buttons (VoiceOver: "月曜日、オン").
private struct WeekdayToggles: View {
    let selected: Set<Int>
    let onChange: (Set<Int>) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<7, id: \.self) { w in
                Toggle(isOn: Binding(
                    get: { selected.contains(w) },
                    set: { on in
                        var s = selected
                        if on { s.insert(w) } else { s.remove(w) }
                        onChange(s)
                    }
                )) {
                    Text(Format.weekdayLabels[w])
                        .frame(minWidth: 28, minHeight: 28)
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .accessibilityLabel("\(Format.weekdayLabels[w])曜日")
            }
        }
    }
}

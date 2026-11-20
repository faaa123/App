import StudyCore
import SwiftUI

/// Named schedules, optionally applied automatically on chosen weekdays.
struct PresetsView: View {
    @Environment(StudyController.self) private var study
    @State private var askingName = false
    @State private var newName = ""
    @State private var confirming: PresetAction?

    enum PresetAction: Identifiable {
        case delete(Preset), load(Preset)
        var id: String {
            switch self {
            case .delete(let p): "d" + p.id
            case .load(let p): "l" + p.id
            }
        }
        var preset: Preset {
            switch self {
            case .delete(let p), .load(let p): p
            }
        }
    }

    var body: some View {
        List {
            Section {
                Text("曜日を選ぶと、その曜日になったとき（4:00〜）自動でスケジュールを置き換えます。同じ曜日に複数ある場合は、後から曜日を設定した方が優先されます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            if study.presets.isEmpty {
                Text("プリセットはまだありません")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .foregroundStyle(.secondary)
            }
            ForEach(study.presets) { p in
                Section {
                    PresetCard(preset: p, onDelete: { confirming = .delete(p) }, onLoad: { confirming = .load(p) })
                }
            }
        }
        .readableWidth()
        .navigationTitle("プリセット")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("現在のスケジュールを保存", systemImage: "square.and.arrow.down") {
                    newName = ""
                    askingName = true
                }
                .labelStyle(.titleAndIcon)
                .disabled(study.blocks.isEmpty)
            }
        }
        .alert("プリセット名", isPresented: $askingName) {
            TextField("名前", text: $newName)
            Button("キャンセル", role: .cancel) {}
            Button("保存") {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { study.saveAsPreset(name: name) }
            }
            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .confirmationDialog(dialogTitle, isPresented: confirmingBinding, titleVisibility: .visible,
                            presenting: confirming) { action in
            switch action {
            case .delete(let p):
                Button("削除", role: .destructive) { study.deletePreset(id: p.id) }
            case .load(let p):
                Button("読み込む") { study.applyPreset(id: p.id) }
            }
        } message: { action in
            switch action {
            case .delete: Text("現在のスケジュールは変わりません。")
            case .load: Text("現在のスケジュールを置き換えます。")
            }
        }
    }

    private var dialogTitle: String {
        switch confirming {
        case .delete(let p)?: "「\(p.name)」を削除しますか？"
        case .load(let p)?: "「\(p.name)」を読み込みますか？"
        case nil: ""
        }
    }

    private var confirmingBinding: Binding<Bool> {
        Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })
    }
}

private struct PresetCard: View {
    let preset: Preset
    let onDelete: () -> Void
    let onLoad: () -> Void
    @Environment(StudyController.self) private var study

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) { title; summary }
                VStack(alignment: .leading, spacing: 4) { title; summary }
            }
            WeekdayToggles(selected: preset.weekdays) { study.setPresetWeekdays(id: preset.id, $0) }
            HStack {
                Spacer()
                Button("削除", role: .destructive, action: onDelete)
                    .buttonStyle(.glass)
                Button("読み込む", action: onLoad)
                    .buttonStyle(.glassProminent)
            }
        }
        .padding(.vertical, 6)
    }

    private var title: some View { Text(preset.name).font(.headline) }
    private var summary: some View {
        Text("\(preset.blocks.count)ブロック・勉強\(Format.minutes(totalStudyMinutes(preset.blocks)))")
            .foregroundStyle(.secondary)
    }
}

private struct WeekdayToggles: View {
    let selected: Set<Int>
    let onChange: (Set<Int>) -> Void

    var body: some View {
        HStack(spacing: 6) {
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
                        .frame(minWidth: 24)
                }
                .toggleStyle(.button)
                .accessibilityLabel("\(Format.weekdayLabels[w])曜日")
            }
        }
        .buttonStyle(.bordered)
    }
}

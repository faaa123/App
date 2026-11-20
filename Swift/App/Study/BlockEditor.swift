import StudyCore
import SwiftUI

/// Add a block (`editing == nil`) or edit one, in a sheet. The whole schedule
/// after the edit is previewed live, including blocks moved by a cascade.
struct BlockEditor: View {
    let editing: Block?
    @Environment(StudyController.self) private var study
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type: BlockType = .study
    @State private var start = 0
    @State private var end = 0
    @State private var cascade = false
    @State private var newId = ""
    @State private var loaded = false

    var body: some View {
        // The schedule can change underneath (4:00 rollover, weekday preset);
        // the preview is recomputed from the current one on every render.
        let result = preview()
        NavigationStack {
            Form {
                Section {
                    Picker("種類", selection: $type) {
                        ForEach(BlockType.allCases, id: \.self) { t in
                            Label(BlockStyle.of(t).label, systemImage: BlockStyle.of(t).icon).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    TextField("名前（空なら「\(BlockStyle.of(type).label)」）", text: $name)
                }
                Section {
                    OffsetPicker(label: "開始", offset: $start, isEnd: false)
                    OffsetPicker(label: "終了", offset: $end, isEnd: true)
                }
                if editing != nil {
                    Section {
                        Picker("時刻の変更", selection: $cascade) {
                            Text("このブロックのみ変更").tag(false)
                            Text("以降のブロックも同じ幅だけずらす").tag(true)
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                    let moved = shifted(result)
                    if !moved.isEmpty {
                        Section("連動して動くブロック") {
                            ForEach(moved, id: \.self) { Text($0).monospacedDigit() }
                        }
                    }
                }
                if case .failure(let e) = result {
                    Section {
                        Label(e.message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(editing == nil ? "ブロックを追加" : "ブロックを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", systemImage: "checkmark") { save() }
                        .disabled(!isOk(result))
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        newId = study.newId()
        if let e = editing {
            name = e.name
            type = e.type
            start = e.start
            end = e.end
        } else {
            // Default: right after the last block, 30 minutes.
            var s = study.blocks.last?.end ?? LogicalDay.toOffset(9, 0)
            if s >= LogicalDay.minutesPerDay { s = LogicalDay.minutesPerDay - 30 }
            start = s
            end = min(max(s + 30, s + 1), LogicalDay.minutesPerDay)
        }
    }

    private var effectiveName: String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? BlockStyle.of(type).label : n
    }

    /// The whole schedule after this edit, or an error.
    private func preview() -> EditResult {
        let blocks = study.blocks
        guard end > start else { return .failure(ScheduleError("終了は開始より後にしてください（翌4:00まで）")) }
        guard let e = editing else {
            guard let added = Block.validated(id: newId, name: effectiveName, type: type, start: start, end: end) else {
                return .failure(ScheduleError("終了は開始より後にしてください（翌4:00まで）"))
            }
            let next = blocks + [added]
            if let err = validateSchedule(next) { return .failure(ScheduleError(err)) }
            return .success(next)
        }
        let renamed = blocks.map { $0.id == e.id ? $0.with(name: effectiveName, type: type) : $0 }
        return cascade
            ? applyCascadeShift(renamed, id: e.id, newStart: start, newEnd: end)
            : applySingleChange(renamed, id: e.id, newStart: start, newEnd: end)
    }

    private func isOk(_ r: EditResult) -> Bool {
        if case .success = r { return true }
        return false
    }

    /// "名前：9:00〜10:00 → 9:30〜10:30" for every other block that moves.
    private func shifted(_ r: EditResult) -> [String] {
        guard let e = editing, cascade, case .success(let after) = r else { return [] }
        let before = Dictionary(study.blocks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return sortedByStart(after).compactMap { b in
            guard b.id != e.id, let old = before[b.id], old.start != b.start else { return nil }
            return "\(b.name)：\(rangeLabel(old)) → \(rangeLabel(b))"
        }
    }

    private func save() {
        // Recomputed against the current schedule at the moment of saving.
        guard case .success(let blocks) = preview() else { return }
        study.setBlocks(blocks)
        dismiss()
    }
}

/// Fill a time range with study/rest repeats.
struct PomodoroSheet: View {
    @Environment(StudyController.self) private var study
    @Environment(\.dismiss) private var dismiss
    @State private var start = 0
    @State private var end = 0
    @State private var studyMinutes = 25
    @State private var restMinutes = 5
    @State private var loaded = false

    var body: some View {
        let generated = pomodoroFill(start: start, end: end, studyMinutes: studyMinutes,
                                     restMinutes: restMinutes) { UUID().uuidString.lowercased() }
        let err = end <= start
            ? "終了は開始より後にしてください（翌4:00まで）"
            : validateSchedule(study.blocks + generated)
        NavigationStack {
            Form {
                Section {
                    OffsetPicker(label: "開始", offset: $start, isEnd: false)
                    OffsetPicker(label: "終了", offset: $end, isEnd: true)
                }
                Section {
                    MinuteStepper(label: "勉強", value: $studyMinutes, range: 5...180)
                    MinuteStepper(label: "休憩", value: $restMinutes, range: 0...60)
                }
                Section {
                    Text("\(generated.count)個のブロック（勉強\(Format.minutes(totalStudyMinutes(generated)))）を追加します")
                    if let err {
                        Label(err, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("ポモドーロで敷き詰める")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加", systemImage: "checkmark") {
                        if study.addBlocks(generated) == nil { dismiss() }
                    }
                    .disabled(err != nil || generated.isEmpty)
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            var s = study.blocks.last?.end ?? LogicalDay.toOffset(9, 0)
            if s >= LogicalDay.minutesPerDay { s = LogicalDay.minutesPerDay - 60 }
            start = s
            end = min(max(s + 120, s + 1), LogicalDay.minutesPerDay)
        }
    }
}

import Foundation
import Observation
import StudyCore

/// Registers schedule and preset edits with the system UndoManager, so they
/// can be undone and redone with ⌘Z / ⇧⌘Z, the three-finger gestures and
/// the 取り消す button of the confirmation toast. Every step is unlimited:
/// redo re-registers undo and vice versa.
@MainActor
@Observable
final class ScheduleUndo {
    let study: StudyController
    /// The window's undo manager, captured at the last edit.
    @ObservationIgnored private weak var undoManager: UndoManager?

    init(study: StudyController) {
        self.study = study
    }

    /// Runs `change`; if it changed the schedule or presets, registers its
    /// undo under `actionName` (shown as "取り消す - <actionName>").
    func perform(_ actionName: String, undoManager: UndoManager?, _ change: () -> Void) {
        let before = study.snapshot
        change()
        guard before != study.snapshot, let undoManager else { return }
        self.undoManager = undoManager
        register(before, actionName)
    }

    func undo() { undoManager?.undo() }

    private func register(_ state: StudyController.Snapshot, _ actionName: String) {
        guard let um = undoManager else { return }
        um.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                // Restoring registers the inverse step (redo while undoing).
                let current = target.study.snapshot
                target.study.restore(state)
                target.register(current, actionName)
            }
        }
        um.setActionName(actionName)
    }
}

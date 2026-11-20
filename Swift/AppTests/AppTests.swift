import StudyCore
import SwiftUI
import Testing
import UIKit
@testable import StudyApp

@MainActor
func makeStudy(_ blocks: [Block] = []) -> StudyController {
    let c = StudyController(store: MemoryStudyStore(), chimes: NoopChimeScheduler()) {
        Instant(local: LocalDateTime(year: 2026, month: 11, day: 20, hour: 12, minute: 10), epochMillis: 0)
    }
    c.load()
    if !blocks.isEmpty { c.setBlocks(blocks) }
    return c
}

@MainActor
let sharedChimes = NotificationChimeScheduler()

/// Everything the screens read from the environment.
@MainActor
func hosted(_ view: some View, _ study: StudyController) -> some View {
    view
        .environment(study)
        .environment(AppRouter())
        .environment(ScheduleUndo(study: study))
        .environment(sharedChimes)
}

/// Renders a view offscreen at a size, so layout code paths run.
@MainActor
func render(_ view: some View, width: CGFloat, height: CGFloat) -> UIImage? {
    let r = ImageRenderer(content: view.frame(width: width, height: height))
    r.proposedSize = ProposedViewSize(width: width, height: height)
    return r.uiImage
}

func o(_ h: Int, _ m: Int) -> Int { LogicalDay.toOffset(h, m) }

@MainActor
struct AppTests {
    @Test func rootViewRenders() {
        #expect(render(hosted(RootView(), makeStudy()), width: 1024, height: 768) != nil)
    }

    @Test(arguments: [ColorScheme.dark, .light])
    func nowViewFitsNarrowSplitView(scheme: ColorScheme) {
        let study = makeStudy([
            Block(id: "a", name: "数学の過去問演習", type: .study, start: o(12, 0), end: o(13, 30)),
            Block(id: "b", name: "休憩", type: .rest, start: o(13, 30), end: o(13, 45)),
        ])
        let view = hosted(NavigationStack { NowView() }, study)
            .dynamicTypeSize(.accessibility3)
            .environment(\.colorScheme, scheme)
        #expect(render(view, width: 590, height: 420) != nil)
    }

    @Test func nowViewEmptyState() {
        #expect(render(hosted(NavigationStack { NowView() }, makeStudy()), width: 800, height: 600) != nil)
    }

    @Test func scheduleScreensRender() {
        let study = makeStudy([
            Block(id: "a", name: "勉強", type: .study, start: o(9, 0), end: o(10, 0)),
            Block(id: "b", name: "散歩", type: .rest, start: o(10, 0), end: o(10, 15)),
        ])
        study.saveAsPreset(name: "平日")
        study.saveAsPreset(name: "週末")
        study.setPresetWeekdays(id: study.presets[0].id, [1, 2, 3])
        study.setPresetWeekdays(id: study.presets[1].id, [3, 6])
        for view in [
            AnyView(NavigationStack { ScheduleView() }),
            AnyView(NavigationStack { PresetsView() }),
            AnyView(BlockEditor(editing: study.blocks[0])),
            AnyView(BlockEditor(editing: nil)),
            AnyView(PomodoroSheet()),
        ] {
            #expect(render(hosted(view, study), width: 600, height: 800) != nil)
        }
    }

    @Test func statsRendersAndListsDaysOldestFirst() {
        let study = makeStudy([Block(id: "a", name: "勉強", type: .study, start: 300, end: 400)])
        #expect(render(hosted(NavigationStack { StatsView() }, study), width: 400, height: 900) != nil)
        let days = StatsView.lastDays(7, today: study.today, byDate: study.minutesByDate())
        #expect(days.count == 7)
        #expect(days.last?.date == study.today)
        #expect(days.last?.isToday == true)
        #expect(days.last?.minutes == 100)
    }

    @Test func undoRestoresAndRedoReapplies() {
        let study = makeStudy([Block(id: "a", name: "勉強", type: .study, start: o(9, 0), end: o(10, 0))])
        let undo = ScheduleUndo(study: study)
        let um = UndoManager()
        um.groupsByEvent = false
        um.beginUndoGrouping()
        undo.perform("削除", undoManager: um) { study.deleteBlock(id: "a") }
        um.endUndoGrouping()
        #expect(study.blocks.isEmpty)
        #expect(um.undoActionName == "削除")
        um.undo()
        #expect(study.blocks.map(\.id) == ["a"])
        um.redo()
        #expect(study.blocks.isEmpty)
    }

    @Test func unchangedEditRegistersNothing() {
        let study = makeStudy()
        let um = UndoManager()
        ScheduleUndo(study: study).perform("なし", undoManager: um) {}
        #expect(!um.canUndo)
    }
}

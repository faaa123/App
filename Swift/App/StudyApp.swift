import StudyCore
import SwiftUI

@main
struct StudyApp: SwiftUI.App {
    @State private var study: StudyController
    @State private var undo: ScheduleUndo
    @State private var router = AppRouter()
    @State private var chimes: NotificationChimeScheduler
    /// The 地図 tab: what the map shows, and the projected map data.
    @State private var mapSettings = MapSettings()
    @State private var atlas = AtlasModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let chimes = NotificationChimeScheduler()
        let study = StudyApp.makeController(chimes: chimes)
        _chimes = State(initialValue: chimes)
        _study = State(initialValue: study)
        _undo = State(initialValue: ScheduleUndo(study: study))
    }

    var body: some Scene {
        WindowGroup {
            // Follows the system appearance (HIG: no app-specific setting);
            // both appearances are designed, dark first.
            RootView()
                .environment(study)
                .environment(router)
                .environment(chimes)
                .environment(undo)
                .environment(mapSettings)
                .environment(atlas)
                .task { await runDayTimer() }
        }
        .commands { AppCommands(router: router) }
        .onChange(of: scenePhase) { _, phase in
            // On resume: finalize past days, apply the weekday preset, re-plan.
            if phase == .active {
                study.refresh()
                chimes.refreshAuthorization()
            }
        }
    }

    @MainActor
    static func makeController(chimes: any ChimeScheduler) -> StudyController {
        let store: any StudyStore
        do {
            store = try FileStudyStore.applicationSupport()
        } catch {
            print("Application Support unavailable, data will not persist: \(error)")
            store = MemoryStudyStore()
        }
        let c = StudyController(store: store, chimes: chimes) { Instant(Date()) }
        c.load()
        return c
    }

    /// Wakes just after each 4:00 so the new day shows without delay.
    private func runDayTimer() async {
        while !Task.isCancelled {
            let next = study.nextDayStart() ?? Date().addingTimeInterval(3600)
            let wait = max(next.timeIntervalSinceNow + 1, 1)
            try? await Task.sleep(for: .seconds(wait))
            if Task.isCancelled { return }
            study.refresh()
        }
    }
}

import StudyCore
import SwiftUI

@main
struct StudyApp: SwiftUI.App {
    @State private var study = StudyApp.makeController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(study)
                .preferredColorScheme(.dark)
                .task { await runDayTimer() }
        }
        .onChange(of: scenePhase) { _, phase in
            // On resume: finalize past days, apply the weekday preset, re-plan.
            if phase == .active { study.refresh() }
        }
    }

    @MainActor
    static func makeController() -> StudyController {
        let store: any StudyStore
        do {
            store = try FileStudyStore.applicationSupport()
        } catch {
            print("Application Support unavailable, data will not persist: \(error)")
            store = MemoryStudyStore()
        }
        let c = StudyController(store: store, chimes: NotificationChimeScheduler()) { Instant(Date()) }
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

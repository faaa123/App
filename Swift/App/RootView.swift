import StudyCore
import SwiftUI

enum AppTab: Hashable {
    case now, schedule, stats, board
}

/// Which tab is selected, so screens can send the user elsewhere (e.g. the
/// empty Now screen opens スケジュール).
@MainActor
@Observable
final class AppRouter {
    var tab: AppTab = .now
}

/// Top-level tabs: the floating Liquid Glass tab bar at the top on iPadOS 26.
/// Tab bar only, never a sidebar (the user finds a sidebar in the way).
struct RootView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("今", systemImage: "timer", value: AppTab.now) {
                NavigationStack { NowView() }
            }
            Tab("スケジュール", systemImage: "calendar.day.timeline.left", value: AppTab.schedule) {
                NavigationStack { ScheduleView() }
            }
            Tab("統計", systemImage: "chart.bar.fill", value: AppTab.stats) {
                NavigationStack { StatsView() }
            }
            Tab("ボード", systemImage: "pencil.and.scribble", value: AppTab.board) {
                BoardView()
            }
        }
        .tabViewStyle(.tabBarOnly)
    }
}

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
    /// Set by the ブロックを追加 command (⌘N); the schedule screen opens its
    /// editor and clears it (also when it first appears).
    var addBlockPending = false

    func requestAddBlock() {
        tab = .schedule
        addBlockPending = true
    }
}

/// Menu bar commands (iPadOS 26 shows them in the menu bar and the ⌘ key
/// overlay).
struct AppCommands: Commands {
    let router: AppRouter

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("ブロックを追加") { router.requestAddBlock() }
                .keyboardShortcut("n")
        }
        CommandMenu("移動") {
            Button("今") { router.tab = .now }.keyboardShortcut("1")
            Button("スケジュール") { router.tab = .schedule }.keyboardShortcut("2")
            Button("統計") { router.tab = .stats }.keyboardShortcut("3")
            Button("ボード") { router.tab = .board }.keyboardShortcut("4")
        }
    }
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

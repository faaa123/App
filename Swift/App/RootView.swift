import SwiftUI

enum AppTab: Hashable {
    case now, schedule, stats, board
}

/// Top-level tabs. On iPadOS 26 this is the floating Liquid Glass tab bar.
/// No sidebar: the tab view keeps its default (non sidebar-adaptable) style.
struct RootView: View {
    @State private var tab: AppTab = .now

    var body: some View {
        TabView(selection: $tab) {
            Tab("今", systemImage: "timer", value: AppTab.now) {
                NavigationStack {
                    NowView()
                }
            }
            Tab("スケジュール", systemImage: "list.bullet", value: AppTab.schedule) {
                NavigationStack {
                    Text("スケジュール")
                        .navigationTitle("スケジュール")
                }
            }
            Tab("統計", systemImage: "chart.bar", value: AppTab.stats) {
                NavigationStack {
                    Text("統計")
                        .navigationTitle("統計")
                }
            }
            Tab("ボード", systemImage: "pencil.tip", value: AppTab.board) {
                Text("ボード")
            }
        }
    }
}

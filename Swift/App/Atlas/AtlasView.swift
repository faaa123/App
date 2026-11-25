import GeoCore
import SwiftUI

/// The 地図 tab: a white map that fills the screen, one theme at a time
/// (picked in the toolbar), with other themes overlaid on request.
struct AtlasView: View {
    /// Reopens the theme the user left.
    @SceneStorage("mapTheme") private var theme: Theme = .plates
    @Environment(MapSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showCredits = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            ZStack(alignment: .bottomLeading) {
                // Edge to edge, under the glass bars, like a maps app.
                // The reader spans the bars too, so its insets say where they are.
                GeometryReader { geo in
                    MapView(primary: theme, insets: geo.safeAreaInsets)
                        .ignoresSafeArea()
                }
                .ignoresSafeArea()
                if settings.showLegend {
                    VStack(alignment: .leading, spacing: 8) {
                        LegendView(theme: theme, season: settings.season)
                        ForEach(Theme.allCases.filter { $0 != theme && settings.overlays.contains($0) }) { t in
                            LegendView(theme: t, season: settings.season)
                        }
                    }
                    .padding()
                }
            }
            .sheet(isPresented: $showCredits) { CreditsView() }
            .navigationTitle(theme.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("主題", selection: $theme) {
                        ForEach(Theme.allCases) { t in
                            Text(t.tabTitle).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                if settings.themes(primary: theme).contains(.winds) {
                    ToolbarItem(placement: .topBarLeading) {
                        Picker("季節", selection: $settings.season) {
                            ForEach(Season.allCases) { Text($0.name).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    overlayMenu
                    displayMenu
                    Button("全体を表示", systemImage: "arrow.down.right.and.arrow.up.left") {
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.35)) {
                            settings.scale = 1
                            settings.offset = .zero
                        }
                    }
                    .disabled(settings.scale == 1 && settings.offset == .zero)
                }
            }
        }
    }

    private var overlayMenu: some View {
        Menu("重ねて表示", systemImage: "square.3.layers.3d") {
            ForEach(Theme.allCases.filter { $0 != theme }) { t in
                Toggle(t.title, systemImage: t.symbol, isOn: Binding(
                    get: { settings.overlays.contains(t) },
                    set: { on in
                        if on { settings.overlays.insert(t) } else { settings.overlays.remove(t) }
                    }))
            }
            if !settings.overlays.isEmpty {
                Divider()
                Button("重ねた主題をすべて外す", systemImage: "xmark") { settings.overlays.removeAll() }
            }
        }
    }

    private var displayMenu: some View {
        @Bindable var settings = settings
        return Menu("表示", systemImage: "globe") {
            Picker("図法", systemImage: "map", selection: $settings.projection) {
                ForEach(Projection.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.menu)
            Picker("中心の経線", systemImage: "arrow.left.and.right", selection: $settings.centralMeridian) {
                Text("0°（大西洋が中央）").tag(0.0)
                Text("150°E（太平洋が中央）").tag(150.0)
            }
            .pickerStyle(.menu)
            Divider()
            Toggle("地名・名称", systemImage: "character.textbox", isOn: $settings.showLabels)
            Toggle("凡例", systemImage: "list.bullet.rectangle", isOn: $settings.showLegend)
            Divider()
            Button("データの出典", systemImage: "info.circle") { showCredits = true }
        }
    }
}

/// Where the map data comes from (attribution the licenses ask for).
struct CreditsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("地図") {
                    LabeledContent("海岸線・国境・湖・河川", value: "Natural Earth（1:110m。拡大すると1:50m・1:10mに切り替え。河川は1:50mを簡略化）")
                }
                Section("プレート境界") {
                    LabeledContent("PB2002", value: "Bird, P. (2003) An updated digital model of plate boundaries. ODC-BY")
                }
                Section("気候区分") {
                    LabeledContent("ケッペン＝ガイガー（1951–2000）",
                                   value: "Kottek, M. et al. (2006)。0.5°格子を高校の区分にまとめてポリゴン化")
                }
                Section {
                    Text("海流・恒常風・気圧帯・造山帯・山脈は、教科書の図をもとにした模式図です。")
                }
            }
            .navigationTitle("データの出典")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
    }
}

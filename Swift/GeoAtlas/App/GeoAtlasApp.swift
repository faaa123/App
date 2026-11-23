import GeoCore
import SwiftUI

@main
struct GeoAtlasApp: SwiftUI.App {
    @State private var settings = MapSettings()
    @State private var atlas = AtlasModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(atlas)
        }
    }
}


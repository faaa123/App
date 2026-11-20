import Testing
@testable import StudyApp

@MainActor
struct AppTests {
    @Test func rootViewBuilds() {
        _ = RootView().body
    }
}

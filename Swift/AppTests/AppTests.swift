import StudyCore
import SwiftUI
import Testing
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

/// Renders a view offscreen at a size, so layout code paths run.
@MainActor
func render(_ view: some View, width: CGFloat, height: CGFloat) -> UIImage? {
    let r = ImageRenderer(content: view.frame(width: width, height: height))
    r.proposedSize = ProposedViewSize(width: width, height: height)
    return r.uiImage
}

@MainActor
struct AppTests {
    @Test func rootViewRenders() {
        #expect(render(RootView().environment(makeStudy()), width: 1024, height: 768) != nil)
    }

    @Test func nowViewFitsNarrowSplitView() {
        let o = LogicalDay.toOffset
        let study = makeStudy([
            Block(id: "a", name: "数学の過去問演習", type: .study, start: o(12, 0), end: o(13, 30)),
            Block(id: "b", name: "休憩", type: .rest, start: o(13, 30), end: o(13, 45)),
        ])
        let view = NavigationStack { NowView() }.environment(study)
            .dynamicTypeSize(.accessibility3)
        #expect(render(view, width: 590, height: 420) != nil)
    }
}

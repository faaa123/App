@testable import StudyCore

func o(_ h: Int, _ m: Int) -> Int { LogicalDay.toOffset(h, m) }

func blk(_ id: String, _ t: BlockType, _ s: Int, _ e: Int) -> Block {
    Block(id: id, name: id, type: t, start: s, end: e)
}

func study(_ id: String, _ s: Int, _ e: Int) -> Block { blk(id, .study, s, e) }
func rest(_ id: String, _ s: Int, _ e: Int) -> Block { blk(id, .rest, s, e) }

func dt(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> LocalDateTime {
    LocalDateTime(year: y, month: mo, day: d, hour: h, minute: mi, second: s)
}

func day(_ y: Int, _ m: Int, _ d: Int) -> CivilDate { CivilDate(year: y, month: m, day: d) }

extension EditResult {
    var blocks: [Block]? { try? get() }
    var error: String? {
        if case .failure(let e) = self { return e.message }
        return nil
    }
    var isOk: Bool { blocks != nil }
}

extension NowStatus {
    var inBlock: NowStatus.InBlock? {
        if case .inBlock(let s) = self { return s }
        return nil
    }
}

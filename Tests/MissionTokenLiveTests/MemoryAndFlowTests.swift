import XCTest
@testable import MissionTokenLive

final class MemoryAndFlowTests: XCTestCase {
    func testAnimationClockDoesNotJumpAfterPause() {
        var clock = FlowAnimationClock()
        clock.setRunning(true, at: 100)
        XCTAssertEqual(clock.value(at: 105), 5, accuracy: 0.001)
        clock.setRunning(false, at: 105)
        XCTAssertEqual(clock.value(at: 500), 5, accuracy: 0.001)
        clock.setRunning(true, at: 500)
        XCTAssertEqual(clock.value(at: 502), 7, accuracy: 0.001)
    }

    func testSourceLinksRejectUntrustedSchemesAndTraversal() {
        XCTAssertNil(BrainFact.sourceURL("https://example.invalid"))
        XCTAssertNil(BrainFact.sourceURL("pdf:../../secret"))
        XCTAssertEqual(BrainFact.sourceURL("pdf:juridique/example.pdf")?.lastPathComponent, "example.pdf")
    }

    func testSearchResponseKeepsHistoryStatusAndUniqueProvenance() throws {
        let data = Data("""
        [{"text":"Exemple","kind":"memory","source":"/tmp/a.md","entity":null,"status":"superseded","at":"2026-11-19T10:00:00Z"},
         {"text":"Exemple","kind":"memory","source":"/tmp/b.md","entity":null,"status":"active"}]
        """.utf8)
        let facts = try JSONDecoder().decode([BrainFact].self, from: data)
        XCTAssertEqual(facts[0].status, "superseded")
        XCTAssertNotEqual(facts[0].id, facts[1].id)
        XCTAssertNotNil(BrainFact.date(facts[0].at))
    }
}

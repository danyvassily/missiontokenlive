import XCTest
@testable import MissionTokenLive

final class ModelsTests: XCTestCase {
    func testUnavailableCostNeverDisplaysZero() {
        let cost = CostValue(amount: nil, reliability: .unavailable, source: "aucune API", pricing_version: nil)
        XCTAssertEqual(cost.display, "—")
    }

    func testFrenchCurrencyFormatting() {
        XCTAssertEqual(CostValue.formatFR(12.48), "12,48 $")
    }

    func testReliabilityLabels() {
        XCTAssertEqual(Reliability.calculated.labelFR, "Calculé")
        XCTAssertEqual(Reliability.unavailable.labelFR, "Non disponible")
    }

    func testEngineExposesSnapshot() throws {
        EngineBridge.seedDemoIfNeeded()
        let snapshot = try XCTUnwrap(EngineBridge.snapshot())
        XCTAssertGreaterThanOrEqual(snapshot.tasks.count, 5)
        XCTAssertTrue(snapshot.kpis.contains { $0.key == "cost_today" })
    }

    func testDemoTasksCarryReliability() throws {
        let snapshot = try XCTUnwrap(EngineBridge.snapshot())
        // Aucune tâche ne doit afficher un montant sans étiquette.
        for task in snapshot.tasks {
            XCTAssertFalse(task.cost.source.isEmpty)
            if task.cost.reliability == .unavailable {
                XCTAssertNil(task.cost.amount)
            }
        }
    }
}

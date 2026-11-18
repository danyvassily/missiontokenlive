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

    func testSettingsDecimalCommaAndHideDockPersist() {
        let initial = EngineBridge.settings()
        defer {
            let restoreBudget = initial.budget.map { SettingsView.formatBudgetFR($0) } ?? ""
            EngineBridge.saveSettings(
                budget: restoreBudget,
                warn: Double(initial.warn),
                critical: Double(initial.critical),
                hideDock: initial.hideDock
            )
        }

        XCTAssertTrue(EngineBridge.saveSettings(budget: "125,75", warn: 82, critical: 94, hideDock: true))
        let loaded = EngineBridge.settings()
        XCTAssertEqual(loaded.budget ?? 0, 125.75, accuracy: 0.001)
        XCTAssertEqual(loaded.warn, 82)
        XCTAssertEqual(loaded.critical, 94)
        XCTAssertTrue(loaded.hideDock)
        XCTAssertEqual(SettingsView.formatBudgetFR(loaded.budget ?? 0), "125,75")
    }

    func testRelativeBalanceTimestampFormatting() {
        let now = Date()
        let fiveMinAgo = now.addingTimeInterval(-5 * 60)
        XCTAssertEqual(ProviderBalance.relativeTimestamp(from: fiveMinAgo, now: now), "interrogé il y a 5 min")
    }
}

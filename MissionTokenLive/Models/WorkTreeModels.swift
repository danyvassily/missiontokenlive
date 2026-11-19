
import Foundation

/// Arborescence de travail réelle : Hermès → sessions → délégations/outils → harnais.
/// Alimentée par `mtl_worktree_json` (lecture seule de la base d'Hermès).
struct WorkTree: Codable, Equatable {
    let available: Bool
    let rootLabel: String
    let runningTasks: Int
    let activeSessions: Int
    let branches: [WorkBranch]
    let harnesses: [WorkHarness]

    static let empty = WorkTree(available: false, rootLabel: "Hermès", runningTasks: 0,
                                activeSessions: 0, branches: [], harnesses: [])
}

struct WorkBranch: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let project: String
    let state: String
    let messages: Int
    let tools: [WorkTool]
    let delegations: [WorkDelegation]

    var isActive: Bool { state == "active" }
}

struct WorkTool: Codable, Equatable, Identifiable {
    let name: String
    let count: Int
    var id: String { name }
}

struct WorkDelegation: Codable, Equatable, Identifiable {
    let id: String
    let goal: String
    let state: String
}

struct WorkHarness: Codable, Equatable, Identifiable {
    let name: String
    let detail: String
    let active: Bool
    var id: String { name }
}

/// Horloge monotone d’animation : pause/reprise sans saut ni temps écoulé en arrière-plan.
struct FlowAnimationClock {
    private var elapsed: TimeInterval = 0
    private var startedAt: TimeInterval?

    func value(at time: TimeInterval) -> TimeInterval {
        elapsed + (startedAt.map { max(0, time - $0) } ?? 0)
    }

    mutating func setRunning(_ running: Bool, at time: TimeInterval) {
        if running {
            if startedAt == nil { startedAt = time }
        } else if let start = startedAt {
            elapsed += max(0, time - start)
            startedAt = nil
        }
    }
}

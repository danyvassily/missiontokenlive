
import Foundation

/// Arborescence de travail réelle : Hermès → sessions → délégations/outils → harnais.
/// Alimentée par `mtl_worktree_json` (lecture seule de la base d'Hermès).
struct WorkTree: Codable {
    let available: Bool
    let rootLabel: String
    let runningTasks: Int
    let activeSessions: Int
    let branches: [WorkBranch]
    let harnesses: [WorkHarness]

    static let empty = WorkTree(available: false, rootLabel: "Hermès", runningTasks: 0,
                                activeSessions: 0, branches: [], harnesses: [])
}

struct WorkBranch: Codable, Identifiable {
    let id: String
    let title: String
    let project: String
    let state: String
    let messages: Int
    let tools: [WorkTool]
    let delegations: [WorkDelegation]

    var isActive: Bool { state == "active" }
}

struct WorkTool: Codable, Identifiable {
    let name: String
    let count: Int
    var id: String { name }
}

struct WorkDelegation: Codable, Identifiable {
    let id: String
    let goal: String
    let state: String
}

struct WorkHarness: Codable, Identifiable {
    let name: String
    let detail: String
    let active: Bool
    var id: String { name }
}

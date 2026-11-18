import Foundation
import SwiftUI
import Combine

enum Screen: String, CaseIterable, Identifiable {
    case now, agents, tasks, costs, providers, software, projects, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .now: return "Maintenant"
        case .agents: return "Agents"
        case .tasks: return "Tâches"
        case .costs: return "Coûts & usage"
        case .providers: return "Providers"
        case .software: return "Logiciels"
        case .projects: return "Projets"
        case .settings: return "Réglages"
        }
    }

    var icon: String {
        switch self {
        case .now: return "dot.radiowaves.left.and.right"
        case .agents: return "point.3.connected.trianglepath.dotted"
        case .tasks: return "list.bullet.rectangle"
        case .costs: return "chart.bar.xaxis"
        case .providers: return "creditcard"
        case .software: return "macwindow.on.rectangle"
        case .projects: return "folder"
        case .settings: return "gearshape"
        }
    }
}

/// Source unique de vérité de l'interface.
///
/// Tout vient du moteur Rust (`EngineBridge.snapshot()`). L'interface ne calcule ni
/// coût ni token : elle affiche et met en forme.
@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var snapshot: Snapshot = .empty
    @Published var selection: Screen = .now
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var engineVersion: String = ""
    @Published var searchText: String = ""
    @Published var statusFilter: TaskStatus?
    @Published var showingDemoData: Bool = false

    private var timer: AnyCancellable?

    init() {
        // Permet de capturer un écran précis : MTL_SCREEN=agents ./MissionTokenLive
        if let raw = ProcessInfo.processInfo.environment["MTL_SCREEN"], let screen = Screen(rawValue: raw) {
            selection = screen
        }
        engineVersion = EngineBridge.version
        EngineBridge.seedDemoIfNeeded()
        refresh()
        timer = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        guard let snap = EngineBridge.snapshot() else { return }
        snapshot = snap
        lastRefresh = Date()
    }

    // MARK: - Sélections dérivées

    var orchestrator: Agent? {
        snapshot.agents.first { $0.kind == .orchestrator }
    }

    var subAgents: [Agent] {
        snapshot.agents.filter { $0.kind == .subAgent }
    }

    var activeAgents: [Agent] {
        snapshot.agents.filter { $0.status == .active }
    }

    var costTodayKpi: Kpi? {
        snapshot.kpis.first { $0.key == "cost_today" }
    }

    var budgetKpi: Kpi? {
        snapshot.kpis.first { $0.key == "budget_remaining" }
    }

    /// Dernière tâche connue de l'agent, quel que soit son statut.
    ///
    /// Afficher uniquement les tâches `running` laissait les cartes « En attente d'une
    /// tâche » alors que l'agent avait une tâche terminée ou en erreur.
    func task(for agent: Agent) -> TaskItem? {
        if let id = agent.current_task_id, let match = snapshot.tasks.first(where: { $0.id == id }) {
            return match
        }
        return snapshot.tasks
            .filter { $0.agent_id == agent.id }
            .sorted { $0.started_at > $1.started_at }
            .first
    }

    var filteredTasks: [TaskItem] {
        var items = snapshot.tasks
        if let statusFilter {
            items = items.filter { $0.status == statusFilter }
        }
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            items = items.filter {
                $0.title.lowercased().contains(q)
                    || ($0.project_name ?? "").lowercased().contains(q)
                    || ($0.model ?? "").lowercased().contains(q)
                    || ($0.provider ?? "").lowercased().contains(q)
            }
        }
        return items
    }

    var apiProviders: [Provider] { snapshot.providers.filter { $0.kind != .subscription } }
    var subscriptionProviders: [Provider] { snapshot.providers.filter { $0.kind == .subscription } }

    /// Répartition par agent (coûts connus uniquement), pour la vue Coûts.
    var costByAgent: [(name: String, amount: Double, reliability: Reliability)] {
        var totals: [String: (Double, Reliability)] = [:]
        for task in snapshot.tasks {
            guard let amount = task.cost.amount, task.cost.reliability != .unavailable else { continue }
            let key = task.agent_name ?? "Inconnu"
            let prev = totals[key] ?? (0, task.cost.reliability)
            totals[key] = (prev.0 + amount, prev.1 == .real ? task.cost.reliability : task.cost.reliability)
        }
        return totals.map { ($0.key, $0.value.0, $0.value.1) }.sorted { $0.1 > $1.1 }
    }

    var totalTokensToday: UInt64 {
        snapshot.tasks.reduce(0) { $0 + $1.tokens.total }
    }
}

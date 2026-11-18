import Foundation
import SwiftUI
import Combine

enum Screen: String, CaseIterable, Identifiable {
    case now, agents, flux, tasks, costs, providers, software, projects, brain, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .now: return "Maintenant"
        case .agents: return "Agents"
        case .flux: return "Flux"
        case .tasks: return "Tâches"
        case .costs: return "Coûts & usage"
        case .providers: return "Providers"
        case .software: return "Logiciels"
        case .projects: return "Projets"
        case .brain: return "Cerveau"
        case .settings: return "Réglages"
        }
    }

    var icon: String {
        switch self {
        case .now: return "dot.radiowaves.left.and.right"
        case .agents: return "point.3.connected.trianglepath.dotted"
        case .flux: return "waveform.path.ecg.rectangle"
        case .tasks: return "list.bullet.rectangle"
        case .costs: return "chart.bar.xaxis"
        case .providers: return "creditcard"
        case .software: return "macwindow.on.rectangle"
        case .projects: return "folder"
        case .brain: return "brain.head.profile"
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
    @Published var settings: EngineBridge.Settings = .fallback
    @Published private(set) var brain: BrainStats = .unavailable

    private var timer: AnyCancellable?

    init() {
        // Permet de capturer un écran précis : MTL_SCREEN=agents ./MissionTokenLive
        if let raw = ProcessInfo.processInfo.environment["MTL_SCREEN"], let screen = Screen(rawValue: raw) {
            selection = screen
        }
        engineVersion = EngineBridge.version
        if ProcessInfo.processInfo.environment["MTL_DEMO"] == "1" {
            EngineBridge.seedDemoIfNeeded()
        }
        // Corbeille : purge uniquement les données internes arrivées à échéance (30 jours).
        _ = EngineBridge.sweepTrash()
        if ProcessInfo.processInfo.environment["MTL_IMPORT_KEYS"] == "1" {
            Self.importAllKeys()
        }
        settings = EngineBridge.settings()
        refresh()
        timer = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    /// Mode démonstration : fixtures locales. Sinon, données réelles d'Hermès.
    var isDemo: Bool { ProcessInfo.processInfo.environment["MTL_DEMO"] == "1" }

    /// Import en lot, utilisé par `MTL_IMPORT_KEYS=1` et par le bouton « Tout importer ».
    /// Les valeurs sont lues puis écrites dans le Trousseau ; elles ne sont jamais affichées.
    static func importAllKeys() {
        for key in EngineBridge.keyInventory() where key.present {
            guard let value = EngineBridge.keyValue(key.envVar) else { continue }
            Keychain.store(value, account: key.envVar)
        }
    }

    func refresh() {
        let snap = isDemo ? (EngineBridge.snapshot() ?? .empty) : Self.liveSnapshot()
        snapshot = snap
        brain = EngineBridge.brainStats()
        lastRefresh = Date()
    }

    /// Construit un instantané à partir des sources réelles, sans jamais inventer de coût.
    ///
    /// - tâches : sessions Hermès (`tokens` réels, coût `Non disponible` ou `Calculé`)
    /// - logiciels : présence locale
    /// - agents : Hermès + un agent externe par logiciel détecté
    /// - KPI : coût agrégé seulement s'il existe, sinon `—` avec l'étiquette `Non disponible`
    static func liveSnapshot() -> Snapshot {
        let tasks = EngineBridge.hermesTasks(limit: 120)
        let software = EngineBridge.desktopActivity()

        var agents: [Agent] = [
            Agent(
                id: "ag_hermes", name: "Hermès", kind: .orchestrator, status: .active,
                parent_id: nil, provider: tasks.first?.provider, model: tasks.first?.model,
                current_task_id: tasks.first(where: { $0.status == .running })?.id,
                color_key: "accent/blue", started_at: tasks.first?.started_at
            )
        ]
        for app in software where app.app != "hermes" && app.state != .closed {
            agents.append(Agent(
                id: "ag_\(app.app)", name: app.display_name, kind: .external,
                status: app.presence_only ? .waiting : .active,
                parent_id: nil, provider: nil, model: nil, current_task_id: nil,
                color_key: app.presence_only ? "signal/warn" : "accent/violet",
                started_at: nil
            ))
        }

        // Coût du jour : uniquement les tâches dont le coût porte un montant.
        let cal = Calendar.current
        let todayTasks = tasks.filter { cal.isDateInToday($0.started_at) }
        let known = todayTasks.compactMap { $0.cost.amount }
        let costToday: Kpi
        if known.isEmpty {
            costToday = Kpi(key: "cost_today", label: "Coût aujourd'hui", value: "—",
                            detail: "aucun coût exploitable dans Hermès", reliability: .unavailable, progress: nil)
        } else {
            let total = known.reduce(0, +)
            let worst = todayTasks.map { $0.cost.reliability }.max { $0.rank < $1.rank } ?? .unavailable
            costToday = Kpi(key: "cost_today", label: "Coût aujourd'hui", value: CostValue.formatFR(total),
                            detail: nil, reliability: worst, progress: nil)
        }

        let tokens = tasks.reduce(UInt64(0)) { $0 + $1.tokens.total }
        let kpis: [Kpi] = [
            costToday,
            budgetKpi(todayKnownCost: known.isEmpty ? nil : known.reduce(0, +)),
            Kpi(key: "tokens_month", label: "Tokens mesurés", value: tokensText(tokens),
                detail: "\(tasks.count) sessions Hermès", reliability: tokens > 0 ? .real : .unavailable, progress: nil),
            Kpi(key: "active_agents", label: "Agents actifs", value: "\(agents.filter { $0.status == .active }.count)",
                detail: "\(software.filter { $0.state != .closed }.count) logiciels ouverts", reliability: .real, progress: nil)
        ]

        // Timeline dérivée des sessions récentes — aucun contenu de conversation.
        let timeline: [UsageEvent] = tasks.prefix(12).map { task in
            UsageEvent(
                id: "ev_\(task.id)", at: task.ended_at ?? task.started_at,
                agent_name: "Hermès",
                kind: task.status == .failed ? .taskFailed : (task.status == .running ? .taskProgress : .taskCompleted),
                message: task.title, tokens: task.tokens, cost: task.cost,
                task_id: task.id, running: task.status == .running
            )
        }

        // Providers observés dans les sessions : solde inconnu, donc Non disponible.
        var seen: Set<String> = []
        let providers: [Provider] = tasks.compactMap { task -> Provider? in
            guard let name = task.provider, !seen.contains(name) else { return nil }
            seen.insert(name)
            return Provider(
                id: "prov_\(name)", name: name, kind: .api, availability: .unknown,
                active_model: task.model, cost_today: task.cost,
                balance: CostValue(amount: nil, reliability: .unavailable,
                                   source: "solde non interrogé — activer dans Réglages", pricing_version: nil),
                balance_alert_pct: 20, keychain_ref: nil,
                note: "Solde non disponible via API"
            )
        }

        return Snapshot(generated_at: Date(), kpis: kpis, agents: agents, timeline: timeline,
                        alerts: [], providers: providers, tasks: tasks, software: software, projects: [])
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

    /// Budget restant, uniquement s'il existe un budget ET un coût connu.
    private static func budgetKpi(todayKnownCost: Double?) -> Kpi {
        let settings = EngineBridge.settings()
        guard let budget = settings.budget, budget > 0, let spent = todayKnownCost else {
            return Kpi(key: "budget_remaining", label: "Budget restant", value: "—",
                       detail: "budget ou coût non disponible", reliability: .unavailable, progress: nil)
        }
        let remaining = max(0, budget - spent)
        return Kpi(key: "budget_remaining", label: "Budget restant", value: CostValue.formatFR(remaining),
                   detail: "sur \(CostValue.formatFR(budget))", reliability: .calculated,
                   progress: min(1, max(0, remaining / budget)))
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

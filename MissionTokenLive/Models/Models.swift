import Foundation
import SwiftUI

// Les propriétés portent exactement les noms snake_case du contrat JSON du moteur Rust :
// aucune transformation, aucun champ inventé côté interface.

enum Reliability: String, Codable, CaseIterable {
    case real, calculated, estimated, unavailable

    var labelFR: String {
        switch self {
        case .real: return "Réel"
        case .calculated: return "Calculé"
        case .estimated: return "Estimé"
        case .unavailable: return "Non disponible"
        }
    }

    /// Rang de fiabilité : plus élevé = moins fiable (le pire l'emporte dans un agrégat).
    var rank: Int {
        switch self {
        case .real: return 0
        case .calculated: return 1
        case .estimated: return 2
        case .unavailable: return 3
        }
    }

    var tint: Color {
        switch self {
        case .real: return Theme.ok
        case .calculated: return Theme.accent
        case .estimated: return Theme.violet
        case .unavailable: return Theme.textTertiary
        }
    }
}

struct CostValue: Codable {
    let amount: Double?
    let reliability: Reliability
    let source: String
    let pricing_version: String?

    /// Jamais « 0,00 $ » quand la donnée est absente.
    var display: String {
        guard let amount, reliability != .unavailable else { return "—" }
        // Un montant réel mais inférieur au centime ne doit pas s'afficher « 0,00 $ » :
        // c'est faux et ça laisse croire que la tâche est gratuite.
        if amount > 0 && amount < 0.005 { return "< 0,01 $" }
        return Self.formatFR(amount)
    }

    static func formatFR(_ value: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return (f.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)) + " $"
    }
}

struct Kpi: Codable, Identifiable {
    var id: String { key }
    let key: String
    let label: String
    let value: String
    let detail: String?
    let reliability: Reliability
    let progress: Double?
}

enum AgentKind: String, Codable { case orchestrator, subAgent = "sub_agent", external }
enum AgentStatus: String, Codable {
    case active, waiting, done, error, idle
    var labelFR: String {
        switch self {
        case .active: return "Actif"
        case .waiting: return "En attente"
        case .done: return "Terminé"
        case .error: return "Erreur"
        case .idle: return "Inactif"
        }
    }
    var tint: Color {
        switch self {
        case .active: return Theme.accent
        case .waiting: return Theme.warn
        case .done: return Theme.ok
        case .error: return Theme.error
        case .idle: return Theme.textTertiary
        }
    }
}

struct Agent: Codable, Identifiable {
    let id: String
    let name: String
    let kind: AgentKind
    let status: AgentStatus
    let parent_id: String?
    let provider: String?
    let model: String?
    let current_task_id: String?
    let color_key: String
    let started_at: Date?
}

enum ProjectStatus: String, Codable { case active, archived, trashed }

struct Project: Codable, Identifiable {
    let id: String
    let name: String
    let path: String?
    let status: ProjectStatus
    let budget: Double?
    let created_at: Date
    let archived_at: Date?
    let purge_after: Date?
    let last_activity_at: Date?
}

enum ProviderKind: String, Codable { case api, local, subscription }
enum Availability: String, Codable { case available, degraded, unavailable, unknown }

struct Provider: Codable, Identifiable {
    let id: String
    let name: String
    let kind: ProviderKind
    let availability: Availability
    let active_model: String?
    let cost_today: CostValue
    let balance: CostValue
    let balance_alert_pct: Int
    let keychain_ref: String?
    let note: String?
}

enum TaskStatus: String, Codable {
    case running, waiting, completed, failed, cancelled
    var labelFR: String {
        switch self {
        case .running: return "En cours"
        case .waiting: return "En attente"
        case .completed: return "Terminée"
        case .failed: return "Erreur"
        case .cancelled: return "Annulée"
        }
    }
    var tint: Color {
        switch self {
        case .running: return Theme.accent
        case .waiting: return Theme.warn
        case .completed: return Theme.ok
        case .failed: return Theme.error
        case .cancelled: return Theme.textTertiary
        }
    }
}

struct TokenCounts: Codable {
    let input: UInt64
    let output: UInt64
    let cache_read: UInt64
    let cache_write: UInt64
    let reasoning: UInt64
    var total: UInt64 { input + output + cache_read + cache_write + reasoning }
}

struct TaskItem: Codable, Identifiable {
    let id: String
    let title: String
    let project_id: String?
    let project_name: String?
    let agent_id: String?
    let agent_name: String?
    let provider: String?
    let model: String?
    let status: TaskStatus
    let started_at: Date
    let ended_at: Date?
    let tokens: TokenCounts
    let cost: CostValue
    let error: String?
}

enum EventKind: String, Codable {
    case taskStarted = "task_started", taskProgress = "task_progress", taskCompleted = "task_completed"
    case taskFailed = "task_failed", balanceWarning = "balance_warning", appOpened = "app_opened", note
}

struct UsageEvent: Codable, Identifiable {
    let id: String
    let at: Date
    let agent_name: String
    let kind: EventKind
    let message: String
    let tokens: TokenCounts
    let cost: CostValue
    let task_id: String?
    let running: Bool
}

enum AlertLevel: String, Codable {
    case info, warning, critical
    var tint: Color {
        switch self {
        case .info: return Theme.accent
        case .warning: return Theme.warn
        case .critical: return Theme.error
        }
    }
}

struct Alert: Codable, Identifiable {
    let id: String
    let level: AlertLevel
    let title: String
    let detail: String
    let created_at: Date
    let acknowledged: Bool
    let action_label: String?
}

enum AppState: String, Codable {
    case open, foreground, background, closed
    var labelFR: String {
        switch self {
        case .open: return "Ouvert"
        case .foreground: return "Au premier plan"
        case .background: return "En arrière-plan"
        case .closed: return "Fermé"
        }
    }
    var tint: Color {
        switch self {
        case .open: return Theme.accent
        case .foreground: return Theme.ok
        case .background: return Theme.textSecondary
        case .closed: return Theme.textTertiary
        }
    }
}

struct DesktopAppActivity: Codable, Identifiable {
    let id: String
    let app: String
    let display_name: String
    let version: String?
    let state: AppState
    let since_seconds: UInt64
    let presence_only: Bool
    let note: String?
}

struct Snapshot: Codable {
    let generated_at: Date
    let kpis: [Kpi]
    let agents: [Agent]
    let timeline: [UsageEvent]
    let alerts: [Alert]
    let providers: [Provider]
    let tasks: [TaskItem]
    let software: [DesktopAppActivity]
    let projects: [Project]

    static let empty = Snapshot(
        generated_at: .distantPast, kpis: [], agents: [], timeline: [], alerts: [],
        providers: [], tasks: [], software: [], projects: []
    )
}

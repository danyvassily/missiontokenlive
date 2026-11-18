//! Entités du domaine MissionTokenLive.
//!
//! Toutes les entités sont sérialisables : c'est le contrat JSON échangé entre
//! le moteur Rust et l'interface SwiftUI via la FFI.

use crate::money::{CostValue, Usd};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AgentKind {
    /// Hermès : chef d'orchestre. Toujours mis en avant dans l'interface.
    Orchestrator,
    SubAgent,
    External,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AgentStatus {
    Active,
    Waiting,
    Done,
    Error,
    Idle,
}

impl AgentStatus {
    pub fn label_fr(&self) -> &'static str {
        match self {
            AgentStatus::Active => "Actif",
            AgentStatus::Waiting => "En attente",
            AgentStatus::Done => "Terminé",
            AgentStatus::Error => "Erreur",
            AgentStatus::Idle => "Inactif",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Agent {
    pub id: String,
    pub name: String,
    pub kind: AgentKind,
    pub status: AgentStatus,
    /// Agent parent (sous-agent d'Hermès, par exemple).
    pub parent_id: Option<String>,
    pub provider: Option<String>,
    pub model: Option<String>,
    pub current_task_id: Option<String>,
    /// Clé de couleur du design system (accent/blue, signal/ok, …).
    pub color_key: String,
    pub started_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ProjectStatus {
    Active,
    Archived,
    Trashed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Project {
    pub id: String,
    pub name: String,
    /// Chemin local observé, jamais modifié par l'application.
    pub path: Option<String>,
    pub status: ProjectStatus,
    pub budget: Option<Usd>,
    pub created_at: DateTime<Utc>,
    pub archived_at: Option<DateTime<Utc>>,
    /// Date de purge automatique de la corbeille locale (30 jours).
    pub purge_after: Option<DateTime<Utc>>,
    pub last_activity_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ProviderKind {
    Api,
    Local,
    /// Abonnement (ChatGPT Plus, Gemini Advanced) : présence seulement, pas de compteur.
    Subscription,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Availability {
    Available,
    Degraded,
    Unavailable,
    Unknown,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Provider {
    pub id: String,
    pub name: String,
    pub kind: ProviderKind,
    pub availability: Availability,
    pub active_model: Option<String>,
    pub cost_today: CostValue,
    /// `None` = l'API n'expose pas de solde. Jamais de valeur inventée.
    pub balance: CostValue,
    pub balance_alert_pct: u8,
    /// Secret stocké dans le Trousseau macOS ; jamais la valeur en clair.
    pub keychain_ref: Option<String>,
    pub note: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TaskStatus {
    Running,
    Waiting,
    Completed,
    Failed,
    Cancelled,
}

impl TaskStatus {
    pub fn label_fr(&self) -> &'static str {
        match self {
            TaskStatus::Running => "En cours",
            TaskStatus::Waiting => "En attente",
            TaskStatus::Completed => "Terminée",
            TaskStatus::Failed => "Erreur",
            TaskStatus::Cancelled => "Annulée",
        }
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct TokenCounts {
    pub input: u64,
    pub output: u64,
    pub cache_read: u64,
    pub cache_write: u64,
    pub reasoning: u64,
}

impl TokenCounts {
    pub fn total(&self) -> u64 {
        self.input + self.output + self.cache_read + self.cache_write + self.reasoning
    }

    pub fn is_empty(&self) -> bool {
        self.total() == 0
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TaskItem {
    pub id: String,
    pub title: String,
    pub project_id: Option<String>,
    pub project_name: Option<String>,
    pub agent_id: Option<String>,
    pub agent_name: Option<String>,
    pub provider: Option<String>,
    pub model: Option<String>,
    pub status: TaskStatus,
    pub started_at: DateTime<Utc>,
    pub ended_at: Option<DateTime<Utc>>,
    pub tokens: TokenCounts,
    pub cost: CostValue,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EventKind {
    TaskStarted,
    TaskProgress,
    TaskCompleted,
    TaskFailed,
    BalanceWarning,
    AppOpened,
    Note,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UsageEvent {
    pub id: String,
    pub at: DateTime<Utc>,
    pub agent_name: String,
    pub kind: EventKind,
    pub message: String,
    pub tokens: TokenCounts,
    pub cost: CostValue,
    pub task_id: Option<String>,
    pub running: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AlertLevel {
    Info,
    Warning,
    Critical,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Alert {
    pub id: String,
    pub level: AlertLevel,
    pub title: String,
    pub detail: String,
    pub created_at: DateTime<Utc>,
    pub acknowledged: bool,
    /// Action proposée dans l'interface (« Recharger », « Ajuster »…).
    pub action_label: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AppState {
    Open,
    Foreground,
    Background,
    Closed,
}

impl AppState {
    pub fn label_fr(&self) -> &'static str {
        match self {
            AppState::Open => "Ouvert",
            AppState::Foreground => "Au premier plan",
            AppState::Background => "En arrière-plan",
            AppState::Closed => "Fermé",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DesktopAppActivity {
    pub id: String,
    /// Identifiant stable : hermes, opencode, chatgpt, gemini, antigravity.
    pub app: String,
    pub display_name: String,
    pub version: Option<String>,
    pub state: AppState,
    pub since_seconds: u64,
    /// Vrai si l'application n'expose aucune donnée d'usage (ChatGPT, Gemini hors API).
    pub presence_only: bool,
    pub note: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Kpi {
    pub key: String,
    pub label: String,
    pub value: String,
    pub detail: Option<String>,
    pub reliability: crate::reliability::Reliability,
    /// Progression 0.0–1.0 pour les jauges (budget restant).
    pub progress: Option<f64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Snapshot {
    pub generated_at: DateTime<Utc>,
    pub kpis: Vec<Kpi>,
    pub agents: Vec<Agent>,
    pub timeline: Vec<UsageEvent>,
    pub alerts: Vec<Alert>,
    pub providers: Vec<Provider>,
    pub tasks: Vec<TaskItem>,
    pub software: Vec<DesktopAppActivity>,
    pub projects: Vec<Project>,
}

//! mission-token-storage — persistance locale SQLite.
//!
//! Toutes les écritures concernent la base interne de MissionTokenLive. Aucun accès en
//! écriture n'est fait vers Hermès, OpenCode ou un dépôt : les collecteurs sont en lecture
//! seule, et la suppression d'un projet ne touche que la fiche locale (corbeille 30 jours).

use chrono::{DateTime, Duration, Utc};
use mission_token_core::*;
use rusqlite::{params, Connection, OptionalExtension};
use std::path::Path;

pub const MIGRATION_SQL: &str = include_str!("../sql/001_init.sql");
pub const TRASH_RETENTION_DAYS: i64 = 30;

#[derive(Debug, thiserror::Error)]
pub enum StorageError {
    #[error("erreur SQLite : {0}")]
    Sqlite(#[from] rusqlite::Error),
    #[error("projet introuvable : {0}")]
    ProjectNotFound(String),
    #[error("date invalide : {0}")]
    BadDate(String),
}

pub type Result<T> = std::result::Result<T, StorageError>;

pub struct Db {
    conn: Connection,
}

fn parse_ts(s: &str) -> DateTime<Utc> {
    DateTime::parse_from_rfc3339(s)
        .map(|d| d.with_timezone(&Utc))
        .unwrap_or_else(|_| Utc::now())
}

fn rel_from(s: &str) -> Reliability {
    match s {
        "real" => Reliability::Real,
        "calculated" => Reliability::Calculated,
        "estimated" => Reliability::Estimated,
        _ => Reliability::Unavailable,
    }
}

fn rel_to(r: Reliability) -> &'static str {
    match r {
        Reliability::Real => "real",
        Reliability::Calculated => "calculated",
        Reliability::Estimated => "estimated",
        Reliability::Unavailable => "unavailable",
    }
}

fn agent_kind(s: &str) -> AgentKind {
    match s {
        "orchestrator" => AgentKind::Orchestrator,
        "external" => AgentKind::External,
        _ => AgentKind::SubAgent,
    }
}

fn agent_status(s: &str) -> AgentStatus {
    match s {
        "active" => AgentStatus::Active,
        "waiting" => AgentStatus::Waiting,
        "done" => AgentStatus::Done,
        "error" => AgentStatus::Error,
        _ => AgentStatus::Idle,
    }
}

fn task_status(s: &str) -> TaskStatus {
    match s {
        "running" => TaskStatus::Running,
        "waiting" => TaskStatus::Waiting,
        "completed" => TaskStatus::Completed,
        "failed" => TaskStatus::Failed,
        _ => TaskStatus::Cancelled,
    }
}

fn event_kind(s: &str) -> EventKind {
    match s {
        "task_started" => EventKind::TaskStarted,
        "task_progress" => EventKind::TaskProgress,
        "task_completed" => EventKind::TaskCompleted,
        "task_failed" => EventKind::TaskFailed,
        "balance_warning" => EventKind::BalanceWarning,
        "app_opened" => EventKind::AppOpened,
        _ => EventKind::Note,
    }
}

impl Db {
    /// Ouvre (ou crée) la base et applique les migrations.
    pub fn open(path: impl AsRef<Path>) -> Result<Self> {
        let conn = Connection::open(path)?;
        conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;")?;
        let db = Self { conn };
        db.migrate()?;
        Ok(db)
    }

    /// Base en mémoire — utilisée par les tests et l'aperçu.
    pub fn open_in_memory() -> Result<Self> {
        let conn = Connection::open_in_memory()?;
        conn.execute_batch("PRAGMA foreign_keys=ON;")?;
        let db = Self { conn };
        db.migrate()?;
        Ok(db)
    }

    pub fn migrate(&self) -> Result<()> {
        self.conn.execute_batch(MIGRATION_SQL)?;
        self.conn.execute(
            "INSERT OR IGNORE INTO schema_migrations(version, applied_at) VALUES (1, ?1)",
            params![Utc::now().to_rfc3339()],
        )?;
        Ok(())
    }

    // ---------- écritures ----------

    pub fn upsert_agent(&self, a: &Agent) -> Result<()> {
        let kind = match a.kind {
            AgentKind::Orchestrator => "orchestrator",
            AgentKind::SubAgent => "sub_agent",
            AgentKind::External => "external",
        };
        let status = match a.status {
            AgentStatus::Active => "active",
            AgentStatus::Waiting => "waiting",
            AgentStatus::Done => "done",
            AgentStatus::Error => "error",
            AgentStatus::Idle => "idle",
        };
        self.conn.execute(
            "INSERT INTO agents(id,name,kind,status,parent_id,provider,model,current_task_id,color_key,started_at)
             VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10)
             ON CONFLICT(id) DO UPDATE SET name=excluded.name, kind=excluded.kind, status=excluded.status,
               parent_id=excluded.parent_id, provider=excluded.provider, model=excluded.model,
               current_task_id=excluded.current_task_id, color_key=excluded.color_key, started_at=excluded.started_at",
            params![
                a.id, a.name, kind, status, a.parent_id, a.provider, a.model,
                a.current_task_id, a.color_key, a.started_at.map(|d| d.to_rfc3339())
            ],
        )?;
        Ok(())
    }

    pub fn upsert_project(&self, p: &Project) -> Result<()> {
        let status = match p.status {
            ProjectStatus::Active => "active",
            ProjectStatus::Archived => "archived",
            ProjectStatus::Trashed => "trashed",
        };
        self.conn.execute(
            "INSERT INTO projects(id,name,path,status,budget_usd,created_at,archived_at,purge_after,last_activity_at)
             VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9)
             ON CONFLICT(id) DO UPDATE SET name=excluded.name, path=excluded.path, status=excluded.status,
               budget_usd=excluded.budget_usd, archived_at=excluded.archived_at,
               purge_after=excluded.purge_after, last_activity_at=excluded.last_activity_at",
            params![
                p.id, p.name, p.path, status, p.budget.map(|b| b.0),
                p.created_at.to_rfc3339(), p.archived_at.map(|d| d.to_rfc3339()),
                p.purge_after.map(|d| d.to_rfc3339()), p.last_activity_at.map(|d| d.to_rfc3339())
            ],
        )?;
        Ok(())
    }

    pub fn upsert_provider(&self, p: &Provider) -> Result<()> {
        let kind = match p.kind {
            ProviderKind::Api => "api",
            ProviderKind::Local => "local",
            ProviderKind::Subscription => "subscription",
        };
        let avail = match p.availability {
            Availability::Available => "available",
            Availability::Degraded => "degraded",
            Availability::Unavailable => "unavailable",
            Availability::Unknown => "unknown",
        };
        self.conn.execute(
            "INSERT INTO providers(id,name,kind,availability,active_model,cost_today_amount,cost_today_reliability,cost_today_source,
                balance_amount,balance_reliability,balance_source,balance_alert_pct,keychain_ref,note)
             VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14)
             ON CONFLICT(id) DO UPDATE SET name=excluded.name, kind=excluded.kind, availability=excluded.availability,
               active_model=excluded.active_model, cost_today_amount=excluded.cost_today_amount,
               cost_today_reliability=excluded.cost_today_reliability, cost_today_source=excluded.cost_today_source,
               balance_amount=excluded.balance_amount, balance_reliability=excluded.balance_reliability,
               balance_source=excluded.balance_source, balance_alert_pct=excluded.balance_alert_pct,
               keychain_ref=excluded.keychain_ref, note=excluded.note",
            params![
                p.id, p.name, kind, avail, p.active_model,
                p.cost_today.amount.map(|a| a.0), rel_to(p.cost_today.reliability), p.cost_today.source,
                p.balance.amount.map(|a| a.0), rel_to(p.balance.reliability), p.balance.source,
                p.balance_alert_pct, p.keychain_ref, p.note
            ],
        )?;
        Ok(())
    }

    pub fn upsert_task(&self, t: &TaskItem) -> Result<()> {
        let status = match t.status {
            TaskStatus::Running => "running",
            TaskStatus::Waiting => "waiting",
            TaskStatus::Completed => "completed",
            TaskStatus::Failed => "failed",
            TaskStatus::Cancelled => "cancelled",
        };
        self.conn.execute(
            "INSERT INTO tasks(id,title,project_id,agent_id,provider,model,status,started_at,ended_at,
                tokens_input,tokens_output,tokens_cache_read,tokens_cache_write,tokens_reasoning,
                cost_amount,cost_reliability,cost_source,cost_pricing_version,error)
             VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16,?17,?18,?19)
             ON CONFLICT(id) DO UPDATE SET title=excluded.title, status=excluded.status, ended_at=excluded.ended_at,
               tokens_input=excluded.tokens_input, tokens_output=excluded.tokens_output,
               tokens_cache_read=excluded.tokens_cache_read, tokens_cache_write=excluded.tokens_cache_write,
               tokens_reasoning=excluded.tokens_reasoning, cost_amount=excluded.cost_amount,
               cost_reliability=excluded.cost_reliability, cost_source=excluded.cost_source,
               cost_pricing_version=excluded.cost_pricing_version, error=excluded.error",
            params![
                t.id, t.title, t.project_id, t.agent_id, t.provider, t.model, status,
                t.started_at.to_rfc3339(), t.ended_at.map(|d| d.to_rfc3339()),
                t.tokens.input, t.tokens.output, t.tokens.cache_read, t.tokens.cache_write, t.tokens.reasoning,
                t.cost.amount.map(|a| a.0), rel_to(t.cost.reliability), t.cost.source,
                t.cost.pricing_version, t.error
            ],
        )?;
        Ok(())
    }

    pub fn insert_event(&self, e: &UsageEvent) -> Result<()> {
        let kind = match e.kind {
            EventKind::TaskStarted => "task_started",
            EventKind::TaskProgress => "task_progress",
            EventKind::TaskCompleted => "task_completed",
            EventKind::TaskFailed => "task_failed",
            EventKind::BalanceWarning => "balance_warning",
            EventKind::AppOpened => "app_opened",
            EventKind::Note => "note",
        };
        self.conn.execute(
            "INSERT OR REPLACE INTO events(id,at,agent_name,kind,message,tokens_input,tokens_output,
                tokens_cache_read,tokens_cache_write,tokens_reasoning,cost_amount,cost_reliability,
                cost_source,cost_pricing_version,task_id,running)
             VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16)",
            params![
                e.id, e.at.to_rfc3339(), e.agent_name, kind, e.message,
                e.tokens.input, e.tokens.output, e.tokens.cache_read, e.tokens.cache_write, e.tokens.reasoning,
                e.cost.amount.map(|a| a.0), rel_to(e.cost.reliability), e.cost.source, e.cost.pricing_version,
                e.task_id, if e.running { 1 } else { 0 }
            ],
        )?;
        Ok(())
    }

    pub fn insert_alert(&self, a: &Alert) -> Result<()> {
        let level = match a.level {
            AlertLevel::Info => "info",
            AlertLevel::Warning => "warning",
            AlertLevel::Critical => "critical",
        };
        self.conn.execute(
            "INSERT OR REPLACE INTO alerts(id,level,title,detail,created_at,acknowledged,action_label)
             VALUES(?1,?2,?3,?4,?5,?6,?7)",
            params![a.id, level, a.title, a.detail, a.created_at.to_rfc3339(), a.acknowledged as i32, a.action_label],
        )?;
        Ok(())
    }

    pub fn upsert_software(&self, s: &DesktopAppActivity) -> Result<()> {
        let state = match s.state {
            AppState::Open => "open",
            AppState::Foreground => "foreground",
            AppState::Background => "background",
            AppState::Closed => "closed",
        };
        self.conn.execute(
            "INSERT INTO software(id,app,display_name,version,state,since_seconds,presence_only,note)
             VALUES(?1,?2,?3,?4,?5,?6,?7,?8)
             ON CONFLICT(app) DO UPDATE SET display_name=excluded.display_name, version=excluded.version,
               state=excluded.state, since_seconds=excluded.since_seconds,
               presence_only=excluded.presence_only, note=excluded.note",
            params![s.id, s.app, s.display_name, s.version, state, s.since_seconds as i64, s.presence_only as i32, s.note],
        )?;
        Ok(())
    }

    pub fn set_setting(&self, key: &str, value: &str) -> Result<()> {
        self.conn.execute(
            "INSERT INTO settings(key,value) VALUES(?1,?2) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
            params![key, value],
        )?;
        Ok(())
    }

    pub fn setting(&self, key: &str) -> Result<Option<String>> {
        Ok(self
            .conn
            .query_row("SELECT value FROM settings WHERE key=?1", params![key], |r| r.get(0))
            .optional()?)
    }

    // ---------- lectures ----------

    pub fn agents(&self) -> Result<Vec<Agent>> {
        let mut st = self.conn.prepare(
            "SELECT id,name,kind,status,parent_id,provider,model,current_task_id,color_key,started_at FROM agents",
        )?;
        let rows = st.query_map([], |r| {
            Ok(Agent {
                id: r.get(0)?,
                name: r.get(1)?,
                kind: agent_kind(&r.get::<_, String>(2)?),
                status: agent_status(&r.get::<_, String>(3)?),
                parent_id: r.get(4)?,
                provider: r.get(5)?,
                model: r.get(6)?,
                current_task_id: r.get(7)?,
                color_key: r.get(8)?,
                started_at: r.get::<_, Option<String>>(9)?.map(|s| parse_ts(&s)),
            })
        })?;
        Ok(rows.collect::<std::result::Result<Vec<_>, _>>()?)
    }

    pub fn providers(&self) -> Result<Vec<Provider>> {
        let mut st = self.conn.prepare(
            "SELECT id,name,kind,availability,active_model,cost_today_amount,cost_today_reliability,cost_today_source,
                    balance_amount,balance_reliability,balance_source,balance_alert_pct,keychain_ref,note FROM providers",
        )?;
        let rows = st.query_map([], |r| {
            let kind: String = r.get(2)?;
            let avail: String = r.get(3)?;
            Ok(Provider {
                id: r.get(0)?,
                name: r.get(1)?,
                kind: match kind.as_str() {
                    "local" => ProviderKind::Local,
                    "subscription" => ProviderKind::Subscription,
                    _ => ProviderKind::Api,
                },
                availability: match avail.as_str() {
                    "available" => Availability::Available,
                    "degraded" => Availability::Degraded,
                    "unavailable" => Availability::Unavailable,
                    _ => Availability::Unknown,
                },
                active_model: r.get(4)?,
                cost_today: CostValue {
                    amount: r.get::<_, Option<f64>>(5)?.map(Usd::new),
                    reliability: rel_from(&r.get::<_, String>(6)?),
                    source: r.get(7)?,
                    pricing_version: None,
                },
                balance: CostValue {
                    amount: r.get::<_, Option<f64>>(8)?.map(Usd::new),
                    reliability: rel_from(&r.get::<_, String>(9)?),
                    source: r.get(10)?,
                    pricing_version: None,
                },
                balance_alert_pct: r.get::<_, i64>(11)? as u8,
                keychain_ref: r.get(12)?,
                note: r.get(13)?,
            })
        })?;
        Ok(rows.collect::<std::result::Result<Vec<_>, _>>()?)
    }

    pub fn tasks(&self, limit: usize) -> Result<Vec<TaskItem>> {
        let mut st = self.conn.prepare(
            "SELECT t.id,t.title,t.project_id,p.name,t.agent_id,a.name,t.provider,t.model,t.status,
                    t.started_at,t.ended_at,t.tokens_input,t.tokens_output,t.tokens_cache_read,
                    t.tokens_cache_write,t.tokens_reasoning,t.cost_amount,t.cost_reliability,t.cost_source,
                    t.cost_pricing_version,t.error
             FROM tasks t
             LEFT JOIN projects p ON p.id = t.project_id
             LEFT JOIN agents a ON a.id = t.agent_id
             ORDER BY t.started_at DESC LIMIT ?1",
        )?;
        let rows = st.query_map(params![limit as i64], |r| {
            Ok(TaskItem {
                id: r.get(0)?,
                title: r.get(1)?,
                project_id: r.get(2)?,
                project_name: r.get(3)?,
                agent_id: r.get(4)?,
                agent_name: r.get(5)?,
                provider: r.get(6)?,
                model: r.get(7)?,
                status: task_status(&r.get::<_, String>(8)?),
                started_at: parse_ts(&r.get::<_, String>(9)?),
                ended_at: r.get::<_, Option<String>>(10)?.map(|s| parse_ts(&s)),
                tokens: TokenCounts {
                    input: r.get::<_, i64>(11)? as u64,
                    output: r.get::<_, i64>(12)? as u64,
                    cache_read: r.get::<_, i64>(13)? as u64,
                    cache_write: r.get::<_, i64>(14)? as u64,
                    reasoning: r.get::<_, i64>(15)? as u64,
                },
                cost: CostValue {
                    amount: r.get::<_, Option<f64>>(16)?.map(Usd::new),
                    reliability: rel_from(&r.get::<_, String>(17)?),
                    source: r.get(18)?,
                    pricing_version: r.get(19)?,
                },
                error: r.get(20)?,
            })
        })?;
        Ok(rows.collect::<std::result::Result<Vec<_>, _>>()?)
    }

    pub fn timeline(&self, limit: usize) -> Result<Vec<UsageEvent>> {
        let mut st = self.conn.prepare(
            "SELECT id,at,agent_name,kind,message,tokens_input,tokens_output,tokens_cache_read,
                    tokens_cache_write,tokens_reasoning,cost_amount,cost_reliability,cost_source,
                    cost_pricing_version,task_id,running
             FROM events ORDER BY at DESC LIMIT ?1",
        )?;
        let rows = st.query_map(params![limit as i64], |r| {
            Ok(UsageEvent {
                id: r.get(0)?,
                at: parse_ts(&r.get::<_, String>(1)?),
                agent_name: r.get(2)?,
                kind: event_kind(&r.get::<_, String>(3)?),
                message: r.get(4)?,
                tokens: TokenCounts {
                    input: r.get::<_, i64>(5)? as u64,
                    output: r.get::<_, i64>(6)? as u64,
                    cache_read: r.get::<_, i64>(7)? as u64,
                    cache_write: r.get::<_, i64>(8)? as u64,
                    reasoning: r.get::<_, i64>(9)? as u64,
                },
                cost: CostValue {
                    amount: r.get::<_, Option<f64>>(10)?.map(Usd::new),
                    reliability: rel_from(&r.get::<_, String>(11)?),
                    source: r.get(12)?,
                    pricing_version: r.get(13)?,
                },
                task_id: r.get(14)?,
                running: r.get::<_, i64>(15)? != 0,
            })
        })?;
        Ok(rows.collect::<std::result::Result<Vec<_>, _>>()?)
    }

    pub fn alerts(&self) -> Result<Vec<Alert>> {
        let mut st = self.conn.prepare(
            "SELECT id,level,title,detail,created_at,acknowledged,action_label FROM alerts ORDER BY created_at DESC",
        )?;
        let rows = st.query_map([], |r| {
            let level: String = r.get(1)?;
            Ok(Alert {
                id: r.get(0)?,
                level: match level.as_str() {
                    "critical" => AlertLevel::Critical,
                    "warning" => AlertLevel::Warning,
                    _ => AlertLevel::Info,
                },
                title: r.get(2)?,
                detail: r.get(3)?,
                created_at: parse_ts(&r.get::<_, String>(4)?),
                acknowledged: r.get::<_, i64>(5)? != 0,
                action_label: r.get(6)?,
            })
        })?;
        Ok(rows.collect::<std::result::Result<Vec<_>, _>>()?)
    }

    pub fn software(&self) -> Result<Vec<DesktopAppActivity>> {
        let mut st = self.conn.prepare(
            "SELECT id,app,display_name,version,state,since_seconds,presence_only,note FROM software ORDER BY display_name",
        )?;
        let rows = st.query_map([], |r| {
            let state: String = r.get(4)?;
            Ok(DesktopAppActivity {
                id: r.get(0)?,
                app: r.get(1)?,
                display_name: r.get(2)?,
                version: r.get(3)?,
                state: match state.as_str() {
                    "open" => AppState::Open,
                    "foreground" => AppState::Foreground,
                    "background" => AppState::Background,
                    _ => AppState::Closed,
                },
                since_seconds: r.get::<_, i64>(5)? as u64,
                presence_only: r.get::<_, i64>(6)? != 0,
                note: r.get(7)?,
            })
        })?;
        Ok(rows.collect::<std::result::Result<Vec<_>, _>>()?)
    }

    pub fn projects(&self, status: Option<ProjectStatus>) -> Result<Vec<Project>> {
        let sql = "SELECT id,name,path,status,budget_usd,created_at,archived_at,purge_after,last_activity_at
                   FROM projects ORDER BY name";
        let mut st = self.conn.prepare(sql)?;
        let rows = st.query_map([], |r| {
            let st: String = r.get(3)?;
            Ok(Project {
                id: r.get(0)?,
                name: r.get(1)?,
                path: r.get(2)?,
                status: match st.as_str() {
                    "archived" => ProjectStatus::Archived,
                    "trashed" => ProjectStatus::Trashed,
                    _ => ProjectStatus::Active,
                },
                budget: r.get::<_, Option<f64>>(4)?.map(Usd::new),
                created_at: parse_ts(&r.get::<_, String>(5)?),
                archived_at: r.get::<_, Option<String>>(6)?.map(|s| parse_ts(&s)),
                purge_after: r.get::<_, Option<String>>(7)?.map(|s| parse_ts(&s)),
                last_activity_at: r.get::<_, Option<String>>(8)?.map(|s| parse_ts(&s)),
            })
        })?;
        let all: Vec<Project> = rows.collect::<std::result::Result<Vec<_>, _>>()?;
        Ok(match status {
            Some(s) => all.into_iter().filter(|p| p.status == s).collect(),
            None => all,
        })
    }

    // ---------- cycle de vie des projets (jamais destructif à l'extérieur) ----------

    pub fn archive_project(&self, id: &str) -> Result<()> {
        self.conn.execute(
            "UPDATE projects SET status='archived', archived_at=?2 WHERE id=?1",
            params![id, Utc::now().to_rfc3339()],
        )?;
        Ok(())
    }

    pub fn restore_project(&self, id: &str) -> Result<()> {
        self.conn.execute(
            "UPDATE projects SET status='active', archived_at=NULL, purge_after=NULL WHERE id=?1",
            params![id],
        )?;
        self.conn.execute("DELETE FROM trash WHERE project_id=?1", params![id])?;
        Ok(())
    }

    /// Envoie la fiche en corbeille locale (30 jours). Ne touche à rien d'externe.
    pub fn trash_project(&self, id: &str) -> Result<DateTime<Utc>> {
        let p: Option<String> = self
            .conn
            .query_row("SELECT name FROM projects WHERE id=?1", params![id], |r| r.get(0))
            .optional()?;
        if p.is_none() {
            return Err(StorageError::ProjectNotFound(id.to_string()));
        }
        let now = Utc::now();
        let purge = now + Duration::days(TRASH_RETENTION_DAYS);
        self.conn.execute(
            "UPDATE projects SET status='trashed', purge_after=?2 WHERE id=?1",
            params![id, purge.to_rfc3339()],
        )?;
        self.conn.execute(
            "INSERT OR REPLACE INTO trash(project_id,trashed_at,purge_after,payload_json) VALUES(?1,?2,?3,?4)",
            params![id, now.to_rfc3339(), purge.to_rfc3339(), "{}"],
        )?;
        Ok(purge)
    }

    /// Purge définitive : uniquement les données internes MissionTokenLive.
    pub fn purge_project(&self, id: &str) -> Result<()> {
        self.conn.execute("DELETE FROM tasks WHERE project_id=?1", params![id])?;
        self.conn.execute("DELETE FROM trash WHERE project_id=?1", params![id])?;
        self.conn.execute("DELETE FROM projects WHERE id=?1", params![id])?;
        Ok(())
    }

    // ---------- agrégats ----------

    pub fn sum_cost_between(&self, from: DateTime<Utc>, to: DateTime<Utc>) -> (Usd, Reliability) {
        let mut st = self
            .conn
            .prepare(
                "SELECT cost_amount, cost_reliability FROM tasks
                 WHERE started_at >= ?1 AND started_at < ?2 AND cost_amount IS NOT NULL",
            )
            .ok();
        let mut total = 0.0;
        // On part du meilleur niveau : sinon `worst` resterait bloqué sur Non disponible.
        let mut worst = Reliability::Real;
        if let Some(st) = st.as_mut() {
            if let Ok(rows) = st.query_map(params![from.to_rfc3339(), to.to_rfc3339()], |r| {
                Ok((r.get::<_, f64>(0)?, rel_from(&r.get::<_, String>(1)?)))
            }) {
                for row in rows.flatten() {
                    total += row.0;
                    worst = worst.worst(row.1);
                }
            }
        }
        if total > 0.0 {
            (Usd::new(total), worst)
        } else {
            (Usd::ZERO, Reliability::Unavailable)
        }
    }

    pub fn load_snapshot(&self) -> Result<Snapshot> {
        let tasks = self.tasks(200)?;
        let projects = self.projects(None)?;
        let agents = self.agents()?;
        let timeline = self.timeline(30)?;
        let alerts = self.alerts()?;
        let providers = self.providers()?;
        let software = self.software()?;

        let now = Utc::now();
        let day_start = now.date_naive().and_hms_opt(0, 0, 0).unwrap().and_utc();
        let month_start = now.date_naive().with_day(1).unwrap().and_hms_opt(0, 0, 0).unwrap().and_utc();
        let (today, today_rel) = self.sum_cost_between(day_start, now);
        let (month, month_rel) = self.sum_cost_between(month_start, now);
        let budget: Option<f64> = self.setting("budget.monthly")?.and_then(|v| v.parse().ok());
        let active_agents = agents.iter().filter(|a| a.status == AgentStatus::Active).count();
        let total_tokens: u64 = tasks.iter().filter(|t| t.started_at >= month_start).map(|t| t.tokens.total()).sum();

        let mut kpis = vec![
            Kpi {
                key: "cost_today".into(),
                label: "Coût aujourd'hui".into(),
                value: today.format_fr(),
                detail: None,
                reliability: today_rel,
                progress: None,
            },
            Kpi {
                key: "tokens_month".into(),
                label: "Tokens ce mois".into(),
                value: format_tokens(total_tokens),
                detail: Some("tokens mesurés localement".into()),
                reliability: if total_tokens > 0 { Reliability::Real } else { Reliability::Unavailable },
                progress: None,
            },
        ];
        if let Some(b) = budget {
            let remaining = (b - month.0).max(0.0);
            kpis.push(Kpi {
                key: "budget_remaining".into(),
                label: "Budget restant".into(),
                value: Usd::new(remaining).format_fr(),
                detail: Some(format!("sur {}", Usd::new(b).format_fr())),
                reliability: month_rel,
                progress: Some(if b > 0.0 { (remaining / b).clamp(0.0, 1.0) } else { 0.0 }),
            });
        }
        kpis.push(Kpi {
            key: "active_agents".into(),
            label: "Agents actifs".into(),
            value: active_agents.to_string(),
            detail: Some(format!("{} sous-agents", agents.iter().filter(|a| a.kind == AgentKind::SubAgent).count())),
            reliability: Reliability::Real,
            progress: None,
        });

        Ok(Snapshot { generated_at: now, kpis, agents, timeline, alerts, providers, tasks, software, projects })
    }
}

fn format_tokens(n: u64) -> String {
    if n >= 1_000_000 {
        format!("{:.2} M", n as f64 / 1_000_000.0).replace('.', ",")
    } else if n >= 1_000 {
        format!("{:.1} k", n as f64 / 1_000.0).replace('.', ",")
    } else {
        n.to_string()
    }
}

use chrono::Datelike;

pub mod seed;

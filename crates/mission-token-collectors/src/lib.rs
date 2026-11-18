//! Collecteurs en LECTURE SEULE.
//!
//! Chaque adaptateur observe une source locale et produit des entités du domaine.
//! Règles :
//! - ouverture des bases en `mode=ro` (jamais d'écriture chez Hermès ou OpenCode) ;
//! - aucune requête sur le contenu des conversations (titre, texte, prompt) ;
//! - tout chiffre porte son étiquette de fiabilité.

use chrono::{DateTime, TimeZone, Utc};
use mission_token_core::*;
use rusqlite::Connection;
use std::path::{Path, PathBuf};

#[derive(Debug, thiserror::Error)]
pub enum CollectorError {
    #[error("source absente : {0}")]
    Missing(String),
    #[error("lecture impossible : {0}")]
    Sqlite(#[from] rusqlite::Error),
}

pub type Result<T> = std::result::Result<T, CollectorError>;

/// Contrat commun aux adaptateurs.
pub trait Collector {
    fn name(&self) -> &'static str;
    /// Vrai si la source est présente sur la machine.
    fn is_available(&self) -> bool;
}

fn ro_connection(path: &Path) -> Result<Connection> {
    if !path.exists() {
        return Err(CollectorError::Missing(path.display().to_string()));
    }
    let uri = format!("file:{}?mode=ro&immutable=1", path.display());
    Ok(Connection::open_with_flags(
        uri,
        rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY | rusqlite::OpenFlags::SQLITE_OPEN_URI,
    )?)
}

fn ts_from_unix(v: f64) -> DateTime<Utc> {
    let secs = v.trunc() as i64;
    let nanos = ((v.fract()) * 1e9).max(0.0) as u32;
    Utc.timestamp_opt(secs, nanos).single().unwrap_or_else(Utc::now)
}

/// Hermès : l'unique source réelle de tokens sur cette machine.
///
/// Audit (docs/INTEGRATION_AUDIT.md) : `session_model_usage` contient des compteurs
/// fiables (`input_tokens`, `output_tokens`, `cache_read_tokens`, `reasoning_tokens`,
/// `api_call_count`) mais `estimated_cost_usd` / `actual_cost_usd` valent 0 et
/// `cost_status` vaut `unknown` ou `estimated` avec `cost_source = none`.
/// => tokens = `Real`, coûts = `Unavailable` tant qu'aucun barème validé n'est fourni.
pub struct HermesAdapter {
    pub state_db: PathBuf,
    pub pricing: PricingTable,
}

impl HermesAdapter {
    pub fn default_path() -> PathBuf {
        let home = std::env::var("HOME").unwrap_or_else(|_| ".".into());
        PathBuf::from(home).join(".hermes/state.db")
    }

    pub fn new(state_db: Option<PathBuf>) -> Self {
        Self { state_db: state_db.unwrap_or_else(Self::default_path), pricing: PricingTable::empty() }
    }

    pub fn with_pricing(mut self, pricing: PricingTable) -> Self {
        self.pricing = pricing;
        self
    }

    /// Sessions récentes → tâches. Aucune colonne de contenu n'est lue.
    pub fn recent_tasks(&self, limit: usize) -> Result<Vec<TaskItem>> {
        let conn = ro_connection(&self.state_db)?;
        let mut st = conn.prepare(
            "SELECT id, COALESCE(NULLIF(title,''), 'Session ' || substr(id,1,8)),
                    model, billing_provider, input_tokens, output_tokens, cache_read_tokens,
                    cache_write_tokens, reasoning_tokens, started_at, last_activity_at,
                    message_count, cost_status, estimated_cost_usd, actual_cost_usd
             FROM sessions
             WHERE started_at IS NOT NULL
             ORDER BY started_at DESC LIMIT ?1",
        )?;
        let rows = st.query_map([limit as i64], |r| {
            let provider: Option<String> = r.get(3)?;
            let model: Option<String> = r.get(2)?;
            let tokens = TokenCounts {
                input: r.get::<_, Option<i64>>(4)?.unwrap_or(0).max(0) as u64,
                output: r.get::<_, Option<i64>>(5)?.unwrap_or(0).max(0) as u64,
                cache_read: r.get::<_, Option<i64>>(6)?.unwrap_or(0).max(0) as u64,
                cache_write: r.get::<_, Option<i64>>(7)?.unwrap_or(0).max(0) as u64,
                reasoning: r.get::<_, Option<i64>>(8)?.unwrap_or(0).max(0) as u64,
            };
            let start: f64 = r.get::<_, Option<f64>>(9)?.unwrap_or(0.0);
            let last: Option<f64> = r.get(10)?;
            let actual: Option<f64> = r.get(14)?;
            let estimated: Option<f64> = r.get(13)?;
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                model,
                provider,
                tokens,
                start,
                last,
                r.get::<_, Option<i64>>(11)?.unwrap_or(0),
                actual,
                estimated,
            ))
        })?;
        let mut out = Vec::new();
        for row in rows {
            let (id, title, model, provider, tokens, start, last, msgs, actual, estimated) = row?;
            let provider_name = provider.clone().unwrap_or_else(|| "inconnu".into());
            // Un montant d'API réellement non nul est `Real` ; sinon barème documenté
            // ou `Unavailable`. Jamais 0,00 $ présenté comme réel.
            let cost = match (actual, estimated) {
                (Some(a), _) if a > 0.0 => CostValue::real(Usd::new(a), "montant renvoyé par le provider"),
                (_, Some(e)) if e > 0.0 => CostValue::estimated(Usd::new(e), "estimation du provider"),
                _ => self.pricing.cost_for(
                    provider.as_deref().unwrap_or(""),
                    model.as_deref().unwrap_or(""),
                    &tokens,
                ),
            };
            let running = last.is_none();
            out.push(TaskItem {
                id: id.clone(),
                title,
                project_id: None,
                project_name: None,
                agent_id: Some("ag_hermes".into()),
                agent_name: Some("Hermès".into()),
                provider: Some(provider_name),
                model,
                status: if running { TaskStatus::Running } else { TaskStatus::Completed },
                started_at: ts_from_unix(start),
                ended_at: last.map(ts_from_unix),
                tokens,
                cost,
                error: None,
            });
            let _ = msgs;
        }
        Ok(out)
    }

    /// Usage agrégé par modèle (audit : table `session_model_usage`).
    pub fn usage_by_model(&self) -> Result<Vec<(String, String, u64, u64)>> {
        let conn = ro_connection(&self.state_db)?;
        let mut st = conn.prepare(
            "SELECT model, billing_provider, SUM(input_tokens), SUM(output_tokens)
             FROM session_model_usage GROUP BY model, billing_provider ORDER BY 3 DESC",
        )?;
        let rows = st.query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, Option<String>>(1)?.unwrap_or_default(),
                r.get::<_, Option<i64>>(2)?.unwrap_or(0).max(0) as u64,
                r.get::<_, Option<i64>>(3)?.unwrap_or(0).max(0) as u64,
            ))
        })?;
        Ok(rows.collect::<std::result::Result<Vec<_>, _>>()?)
    }
}

impl Collector for HermesAdapter {
    fn name(&self) -> &'static str { "hermes" }
    fn is_available(&self) -> bool { self.state_db.exists() }
}

/// OpenCode : base `opencode.db`. On ne lit que les compteurs et les dates de session.
pub struct OpenCodeAdapter {
    pub db_path: PathBuf,
}

impl OpenCodeAdapter {
    pub fn default_path() -> PathBuf {
        let home = std::env::var("HOME").unwrap_or_else(|_| ".".into());
        PathBuf::from(home).join(".local/share/opencode/opencode.db")
    }

    pub fn new(db_path: Option<PathBuf>) -> Self {
        Self { db_path: db_path.unwrap_or_else(Self::default_path) }
    }

    pub fn session_count(&self) -> Result<u64> {
        let conn = ro_connection(&self.db_path)?;
        let n: i64 = conn.query_row("SELECT COUNT(*) FROM session", [], |r| r.get(0))?;
        Ok(n.max(0) as u64)
    }
}

impl Collector for OpenCodeAdapter {
    fn name(&self) -> &'static str { "opencode" }
    fn is_available(&self) -> bool { self.db_path.exists() }
}

/// Présence des logiciels : uniquement ouvert / fermé (aucune lecture de contenu).
///
/// `pgrep -x` ne nécessite aucune permission spéciale. L'état « au premier plan »
/// exige `NSWorkspace` côté Swift, ou l'autorisation Accessibilité — laissée désactivée
/// par défaut (voir docs/PRIVACY_AND_LIMITS.md).
pub struct DesktopActivityAdapter;

impl DesktopActivityAdapter {
    pub fn detect() -> Vec<DesktopAppActivity> {
        let apps = [
            ("hermes", "Hermès", "Hermes", false),
            ("opencode", "OpenCode", "opencode", false),
            ("chatgpt", "ChatGPT", "ChatGPT", true),
            ("gemini", "Gemini", "Gemini", true),
            ("antigravity", "Antigravity", "Antigravity", false),
        ];
        apps.iter()
            .map(|(id, display, proc_name, presence_only)| {
                let running = std::process::Command::new("pgrep")
                    .args(["-x", proc_name])
                    .output()
                    .map(|o| o.status.success())
                    .unwrap_or(false);
                DesktopAppActivity {
                    id: format!("sw_{id}"),
                    app: (*id).into(),
                    display_name: (*display).into(),
                    version: None,
                    state: if running { AppState::Open } else { AppState::Closed },
                    since_seconds: 0,
                    presence_only: *presence_only,
                    note: if *presence_only {
                        Some("Présence uniquement — aucune donnée d'usage".into())
                    } else {
                        None
                    },
                }
            })
            .collect()
    }
}

impl Collector for DesktopActivityAdapter {
    fn name(&self) -> &'static str { "desktop_activity" }
    fn is_available(&self) -> bool { true }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture_db(path: &Path) {
        let c = Connection::open(path).unwrap();
        c.execute_batch(
            "CREATE TABLE sessions(id TEXT PRIMARY KEY, title TEXT, model TEXT, billing_provider TEXT,
                input_tokens INTEGER, output_tokens INTEGER, cache_read_tokens INTEGER, cache_write_tokens INTEGER,
                reasoning_tokens INTEGER, started_at REAL, last_activity_at REAL, message_count INTEGER,
                cost_status TEXT, estimated_cost_usd REAL, actual_cost_usd REAL);
             CREATE TABLE session_model_usage(session_id TEXT, model TEXT, billing_provider TEXT,
                input_tokens INTEGER, output_tokens INTEGER);
             INSERT INTO sessions VALUES('s1','Analyse','deepseek-flash','deepseek',1000,250,0,0,0,
                1795000000.0,1795000060.0,4,'unknown',0.0,NULL);",
        )
        .unwrap();
    }

    #[test]
    fn hermes_adapter_reads_tokens_and_refuses_to_invent_cost() {
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("state.db");
        fixture_db(&p);
        let a = HermesAdapter::new(Some(p));
        let tasks = a.recent_tasks(10).unwrap();
        assert_eq!(tasks.len(), 1);
        assert_eq!(tasks[0].tokens.total(), 1250);
        assert_eq!(tasks[0].cost.reliability, Reliability::Unavailable);
        assert_eq!(tasks[0].cost.display(), "—");
    }

    #[test]
    fn hermes_adapter_available_only_when_file_exists() {
        let dir = tempfile::tempdir().unwrap();
        let a = HermesAdapter::new(Some(dir.path().join("absent.db")));
        assert!(!a.is_available());
        assert!(a.recent_tasks(1).is_err());
    }

    #[test]
    fn desktop_activity_never_reports_usage_data() {
        for a in DesktopActivityAdapter::detect() {
            if a.presence_only {
                assert!(a.note.as_deref().unwrap().contains("Présence"));
            }
            assert!(matches!(a.state, AppState::Open | AppState::Closed));
        }
    }
}

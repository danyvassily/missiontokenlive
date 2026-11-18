//! Jeu de données de démonstration.
//!
//! Utilisé pour les captures, les tests UI et le premier lancement tant qu'aucune source
//! réelle n'est branchée. Les montants portent l'étiquette `Calculé` (barème de démo) ou
//! `Non disponible` — jamais `Réel`.

use crate::{Db, Result};
use chrono::{Duration, Utc};
use mission_token_core::*;

pub fn demo(db: &Db) -> Result<()> {
    let now = Utc::now();
    let pricing = PricingTable::demo();

    // --- projets ---
    let projects = vec![
        ("prj_agorax", "Agorax", Some("/Users/dany/projects/agorax"), ProjectStatus::Active, Some(120.0)),
        ("prj_piano", "Atelier Piano", Some("/Users/dany/Documents/atelier-piano"), ProjectStatus::Active, Some(40.0)),
        ("prj_creation", "Création — Token Town", Some("/Users/dany/figcraft-designs/token-town"), ProjectStatus::Archived, None),
        ("prj_free", "Freeparty", None, ProjectStatus::Active, None),
    ];
    for (id, name, path, status, budget) in projects {
        db.upsert_project(&Project {
            id: id.into(),
            name: name.into(),
            path: path.map(|p| p.into()),
            status,
            budget: budget.map(Usd::new),
            created_at: now - Duration::days(30),
            archived_at: if status == ProjectStatus::Archived { Some(now - Duration::days(3)) } else { None },
            purge_after: None,
            last_activity_at: Some(now - Duration::minutes(4)),
        })?;
    }

    // --- agents ---
    let agents = vec![
        ("ag_hermes", "Hermès", AgentKind::Orchestrator, AgentStatus::Active, None, Some("openrouter"), Some("deepseek/deepseek-v4.1-flash"), "accent/blue", Some(now - Duration::minutes(12))),
        ("ag_agorax", "Agorax", AgentKind::SubAgent, AgentStatus::Active, Some("ag_hermes"), Some("openrouter"), Some("deepseek/deepseek-v4.1-flash"), "accent/blue", Some(now - Duration::minutes(12))),
        ("ag_piano", "Atelier Piano", AgentKind::SubAgent, AgentStatus::Waiting, Some("ag_hermes"), Some("deepseek"), Some("deepseek-v4-pro"), "signal/warn", Some(now - Duration::minutes(41))),
        ("ag_veille", "Veille", AgentKind::SubAgent, AgentStatus::Done, Some("ag_hermes"), Some("deepseek"), Some("deepseek-v4-flash"), "signal/ok", Some(now - Duration::hours(2))),
        ("ag_money", "Money", AgentKind::SubAgent, AgentStatus::Error, Some("ag_hermes"), Some("abliteration"), Some("abliterated-model-large"), "signal/error", Some(now - Duration::minutes(7))),
        ("ag_opencode", "OpenCode", AgentKind::External, AgentStatus::Active, None, Some("opencode-zen"), Some("sonnet-5.5"), "accent/violet", Some(now - Duration::minutes(4))),
    ];
    for (id, name, kind, status, parent, provider, model, color, started) in agents {
        db.upsert_agent(&Agent {
            id: id.into(),
            name: name.into(),
            kind,
            status,
            parent_id: parent.map(|p| p.into()),
            provider: provider.map(|p| p.into()),
            model: model.map(|m| m.into()),
            current_task_id: None,
            color_key: color.into(),
            started_at: started,
        })?;
    }

    // --- providers ---
    let providers = vec![
        Provider {
            id: "prov_openrouter".into(),
            name: "OpenRouter".into(),
            kind: ProviderKind::Api,
            availability: Availability::Degraded,
            active_model: Some("deepseek/deepseek-v4.1-flash".into()),
            cost_today: CostValue::calculated(Usd::new(7.92), "tokens mesurés × barème de démo", "demo-2026.11"),
            balance: CostValue::real(Usd::new(12.40), "API OpenRouter /credits (démo)"),
            balance_alert_pct: 20,
            keychain_ref: Some("mtl.provider.openrouter".into()),
            note: Some("Crédit faible : 8 % du seuil d'alerte".into()),
        },
        Provider {
            id: "prov_deepseek".into(),
            name: "DeepSeek".into(),
            kind: ProviderKind::Api,
            availability: Availability::Available,
            active_model: Some("deepseek-v4-flash".into()),
            cost_today: CostValue::calculated(Usd::new(3.18), "tokens mesurés × barème de démo", "demo-2026.11"),
            balance: CostValue::real(Usd::new(4.86), "API DeepSeek /user/balance (démo)"),
            balance_alert_pct: 15,
            keychain_ref: Some("mtl.provider.deepseek".into()),
            note: None,
        },
        Provider {
            id: "prov_ollama".into(),
            name: "Modèles locaux".into(),
            kind: ProviderKind::Local,
            availability: Availability::Available,
            active_model: Some("qwen3-coder".into()),
            cost_today: CostValue::calculated(Usd::ZERO, "exécution locale — aucun coût API", "local"),
            balance: CostValue::unavailable("un modèle local n'a pas de solde"),
            balance_alert_pct: 0,
            keychain_ref: None,
            note: Some("Ollama · 14 modèles installés".into()),
        },
        Provider {
            id: "prov_abliteration".into(),
            name: "Abliteration".into(),
            kind: ProviderKind::Api,
            availability: Availability::Available,
            active_model: Some("abliterated-model-large".into()),
            cost_today: CostValue::unavailable("facturation non exposée"),
            balance: CostValue::unavailable("l'API ne publie pas de solde"),
            balance_alert_pct: 20,
            keychain_ref: Some("mtl.provider.abliteration".into()),
            note: Some("Solde non disponible via API".into()),
        },
        Provider {
            id: "prov_chatgpt".into(),
            name: "ChatGPT Plus".into(),
            kind: ProviderKind::Subscription,
            availability: Availability::Available,
            active_model: None,
            cost_today: CostValue::unavailable("abonnement — pas de coût à l'usage"),
            balance: CostValue::unavailable("aucun compteur de crédits exposé"),
            balance_alert_pct: 0,
            keychain_ref: None,
            note: Some("Suivi de présence uniquement".into()),
        },
        Provider {
            id: "prov_gemini".into(),
            name: "Gemini Advanced".into(),
            kind: ProviderKind::Subscription,
            availability: Availability::Available,
            active_model: None,
            cost_today: CostValue::unavailable("abonnement — pas de coût à l'usage"),
            balance: CostValue::unavailable("aucun compteur de crédits exposé"),
            balance_alert_pct: 0,
            keychain_ref: None,
            note: Some("Suivi de présence uniquement".into()),
        },
    ];
    for p in &providers {
        db.upsert_provider(p)?;
    }

    // --- tâches ---
    struct SeedTask {
        id: &'static str,
        title: &'static str,
        project: Option<&'static str>,
        agent: &'static str,
        provider: &'static str,
        model: &'static str,
        status: TaskStatus,
        mins_ago: i64,
        dur_min: i64,
        ti: u64,
        to: u64,
    }
    let tasks = vec![
        SeedTask { id: "tsk_001", title: "Analyse programme politique — chapitre 3", project: Some("prj_agorax"), agent: "ag_hermes", provider: "openrouter", model: "deepseek/deepseek-v4.1-flash", status: TaskStatus::Running, mins_ago: 12, dur_min: 0, ti: 42180, to: 8940 },
        SeedTask { id: "tsk_010", title: "Analyse programme politique — chapitre 3 (sous-agent)", project: Some("prj_agorax"), agent: "ag_agorax", provider: "openrouter", model: "deepseek/deepseek-v4.1-flash", status: TaskStatus::Running, mins_ago: 11, dur_min: 0, ti: 42180, to: 8940 },
        SeedTask { id: "tsk_002", title: "Revue UI — écrans Token Town", project: Some("prj_creation"), agent: "ag_opencode", provider: "opencode-zen", model: "sonnet-5.5", status: TaskStatus::Running, mins_ago: 4, dur_min: 0, ti: 18400, to: 3120 },
        SeedTask { id: "tsk_003", title: "Veille tech FR — synthèse hebdomadaire", project: Some("prj_agorax"), agent: "ag_veille", provider: "deepseek", model: "deepseek-v4-flash", status: TaskStatus::Completed, mins_ago: 120, dur_min: 9, ti: 128400, to: 21400 },
        SeedTask { id: "tsk_004", title: "Correction des gammes — Atelier Piano", project: Some("prj_piano"), agent: "ag_piano", provider: "deepseek", model: "deepseek-v4-pro", status: TaskStatus::Waiting, mins_ago: 41, dur_min: 0, ti: 9600, to: 1200 },
        SeedTask { id: "tsk_005", title: "Score bankroll — Money", project: None, agent: "ag_money", provider: "abliteration", model: "abliterated-model-large", status: TaskStatus::Failed, mins_ago: 7, dur_min: 1, ti: 3200, to: 480 },
        SeedTask { id: "tsk_006", title: "Extraction des métadonnées — Freeparty", project: Some("prj_free"), agent: "ag_hermes", provider: "openrouter", model: "deepseek/deepseek-v4.1-flash", status: TaskStatus::Completed, mins_ago: 190, dur_min: 6, ti: 51200, to: 8800 },
        SeedTask { id: "tsk_007", title: "Résumé de réunion — L'Almanach", project: None, agent: "ag_hermes", provider: "local", model: "qwen3-coder", status: TaskStatus::Completed, mins_ago: 260, dur_min: 3, ti: 24000, to: 2600 },
        SeedTask { id: "tsk_008", title: "Synchronisation du calendrier travail", project: None, agent: "ag_hermes", provider: "local", model: "qwen3-coder", status: TaskStatus::Completed, mins_ago: 320, dur_min: 1, ti: 8200, to: 640 },
        SeedTask { id: "tsk_009", title: "Conversation ChatGPT — plan éditorial", project: Some("prj_creation"), agent: "ag_hermes", provider: "chatgpt", model: "—", status: TaskStatus::Completed, mins_ago: 400, dur_min: 0, ti: 0, to: 0 },
    ];
    for t in &tasks {
        let tokens = TokenCounts { input: t.ti, output: t.to, ..Default::default() };
        let cost = pricing.cost_for(t.provider, t.model, &tokens);
        let started = now - Duration::minutes(t.mins_ago);
        let ended = if t.dur_min > 0 { Some(started + Duration::minutes(t.dur_min)) } else { None };
        db.upsert_task(&TaskItem {
            id: t.id.into(),
            title: t.title.into(),
            project_id: t.project.map(|p| p.into()),
            project_name: None,
            agent_id: Some(t.agent.into()),
            agent_name: None,
            provider: Some(t.provider.into()),
            model: Some(t.model.into()),
            status: t.status,
            started_at: started,
            ended_at: ended,
            tokens,
            cost,
            error: if t.status == TaskStatus::Failed { Some("Réponse vide du provider (HTTP 200)".into()) } else { None },
        })?;
    }

    // --- timeline ---
    let events = vec![
        ("ev_1", 0, "Hermès", EventKind::TaskProgress, "Analyse du chapitre 3 · 2 480 tokens consommés", 2480u64, 0u64, true, Some("tsk_001")),
        ("ev_2", 1, "OpenCode", EventKind::TaskStarted, "Revue UI démarrée sur 11 écrans", 0, 0, true, Some("tsk_002")),
        ("ev_3", 2, "Hermès", EventKind::Note, "Sous-agent Veille terminé — synthèse enregistrée", 0, 0, false, None),
        ("ev_4", 3, "Money", EventKind::TaskFailed, "Échec du scoring : réponse vide du provider", 3200, 480, false, Some("tsk_005")),
        ("ev_5", 4, "Hermès", EventKind::BalanceWarning, "Crédit OpenRouter à 8 % du seuil d'alerte", 0, 0, false, None),
        ("ev_6", 5, "Hermès", EventKind::TaskCompleted, "Extraction Freeparty terminée — 12 480 tokens", 51200, 8800, false, Some("tsk_006")),
        ("ev_7", 6, "Atelier Piano", EventKind::TaskStarted, "Correction des gammes en attente de validation", 9600, 1200, false, Some("tsk_004")),
    ];
    for (id, mins, agent, kind, msg, ti, to, running, task) in events {
        let tokens = TokenCounts { input: ti, output: to, ..Default::default() };
        db.insert_event(&UsageEvent {
            id: id.into(),
            at: now - Duration::minutes(mins as i64),
            agent_name: agent.into(),
            kind,
            message: msg.into(),
            tokens: tokens.clone(),
            cost: pricing.cost_for("openrouter", "deepseek/deepseek-v4.1-flash", &tokens),
            task_id: task.map(|t| t.into()),
            running,
        })?;
    }

    // --- alertes ---
    db.insert_alert(&Alert {
        id: "alr_1".into(),
        level: AlertLevel::Warning,
        title: "Crédit OpenRouter à 8 %".into(),
        detail: "12,40 $ restants · seuil d'alerte 20 %".into(),
        created_at: now - Duration::minutes(4),
        acknowledged: false,
        action_label: Some("Recharger".into()),
    })?;
    db.insert_alert(&Alert {
        id: "alr_2".into(),
        level: AlertLevel::Info,
        title: "Budget mensuel à 72 %".into(),
        detail: "214,86 $ consommés sur 300 $ · il reste 11 jours".into(),
        created_at: now - Duration::hours(3),
        acknowledged: false,
        action_label: Some("Ajuster".into()),
    })?;

    // --- logiciels ---
    db.upsert_software(&DesktopAppActivity {
        id: "sw_hermes".into(), app: "hermes".into(), display_name: "Hermès".into(), version: Some("1.4.2".into()),
        state: AppState::Open, since_seconds: 5400, presence_only: false, note: Some("3 sessions · 1,24 M tokens".into()),
    })?;
    db.upsert_software(&DesktopAppActivity {
        id: "sw_opencode".into(), app: "opencode".into(), display_name: "OpenCode".into(), version: Some("0.9.4".into()),
        state: AppState::Background, since_seconds: 240, presence_only: false, note: Some("1 session · 248 k tokens".into()),
    })?;
    db.upsert_software(&DesktopAppActivity {
        id: "sw_chatgpt".into(), app: "chatgpt".into(), display_name: "ChatGPT".into(), version: Some("App 1.2026.11".into()),
        state: AppState::Foreground, since_seconds: 900, presence_only: true, note: Some("Aucune donnée d'usage disponible".into()),
    })?;
    db.upsert_software(&DesktopAppActivity {
        id: "sw_gemini".into(), app: "gemini".into(), display_name: "Gemini".into(), version: None,
        state: AppState::Closed, since_seconds: 0, presence_only: true, note: Some("Dernière activité il y a 02 h 15 min".into()),
    })?;
    db.upsert_software(&DesktopAppActivity {
        id: "sw_antigravity".into(), app: "antigravity".into(), display_name: "Antigravity".into(), version: Some("2.1".into()),
        state: AppState::Background, since_seconds: 1500, presence_only: false, note: Some("2 sessions · coût estimé".into()),
    })?;

    db.set_setting("budget.monthly", "300")?;
    db.set_setting("budget.alert.pct", "80")?;
    db.set_setting("budget.critical.pct", "95")?;
    db.set_setting("privacy.local_only", "true")?;
    Ok(())
}

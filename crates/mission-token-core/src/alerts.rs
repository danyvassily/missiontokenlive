//! Moteur d'alertes.
//!
//! Fonction pure : entrées = un instantané + le budget et le total du mois, sortie = alertes.
//! Les identifiants sont déterministes pour qu'une même situation ne produise pas dix alertes.
//!
//! Aucune règle ne déclenche d'action : une alerte informe, l'utilisateur décide.

use crate::domain::{Alert, AlertLevel, Availability, ProjectStatus, Snapshot, TaskStatus};
use chrono::{DateTime, Duration, Utc};

pub struct AlertInputs<'a> {
    pub snapshot: &'a Snapshot,
    pub monthly_budget: Option<f64>,
    /// Dépenses du mois en cours, telles que calculées par le stockage.
    pub month_spent: f64,
    pub now: DateTime<Utc>,
}

const LONG_TASK_MIN_SECONDS: i64 = 600;      // 10 minutes
const LONG_TASK_FACTOR: i64 = 3;              // 3× la médiane de l'agent
const FAILURE_WINDOW_MINUTES: i64 = 30;
const FAILURE_THRESHOLD: usize = 3;

pub fn evaluate(input: &AlertInputs) -> Vec<Alert> {
    let mut out = Vec::new();
    out.extend(budget_alerts(input));
    out.extend(balance_alerts(input));
    out.extend(long_task_alerts(input));
    out.extend(failure_alerts(input));
    out.extend(provider_down_alerts(input));
    out.sort_by(|a, b| b.created_at.cmp(&a.created_at));
    out
}

fn budget_alerts(i: &AlertInputs) -> Vec<Alert> {
    let Some(budget) = i.monthly_budget.filter(|b| *b > 0.0) else { return vec![] };
    let used = i.month_spent / budget;
    let mut out = Vec::new();
    for (pct, level, label) in [
        (1.00, AlertLevel::Critical, "Budget mensuel atteint"),
        (0.90, AlertLevel::Warning, "Budget mensuel à 90 %"),
        (0.80, AlertLevel::Info, "Budget mensuel à 80 %"),
    ] {
        if used >= pct {
            out.push(Alert {
                id: format!("budget-{:.0}", pct * 100.0),
                level,
                title: label.to_string(),
                detail: format!(
                    "{:.2} $ consommés sur {:.2} $ ({:.0} %)",
                    i.month_spent,
                    budget,
                    used * 100.0
                )
                .replace('.', ","),
                created_at: i.now,
                acknowledged: false,
                action_label: Some("Ajuster".into()),
            });
            break; // une seule alerte de budget : la plus grave
        }
    }
    out
}

fn balance_alerts(i: &AlertInputs) -> Vec<Alert> {
    i.snapshot
        .providers
        .iter()
        .filter(|p| !matches!(p.availability, Availability::Unavailable))
        .filter_map(|p| {
            let amount = p.balance.amount?.0;
            // Sans référence de seuil en valeur absolue, on ne peut pas conclure : on se tait
            // plutôt que d'inventer un pourcentage.
            let threshold = p.balance_alert_pct as f64;
            if threshold <= 0.0 || amount > threshold {
                return None;
            }
            Some(Alert {
                id: format!("balance-{}", p.id),
                level: AlertLevel::Warning,
                title: format!("Crédit {} faible", p.name),
                detail: format!("{:.2} $ restants · seuil {:.0} %", amount, threshold).replace('.', ","),
                created_at: i.now,
                acknowledged: false,
                action_label: Some("Recharger".into()),
            })
        })
        .collect()
}

fn long_task_alerts(i: &AlertInputs) -> Vec<Alert> {
    let mut out = Vec::new();
    for agent in &i.snapshot.agents {
        let durations: Vec<i64> = i
            .snapshot
            .tasks
            .iter()
            .filter(|t| t.agent_id.as_deref() == Some(agent.id.as_str()) && t.ended_at.is_some())
            .map(|t| (t.ended_at.unwrap() - t.started_at).num_seconds())
            .collect();
        let running: Vec<_> = i
            .snapshot
            .tasks
            .iter()
            .filter(|t| t.agent_id.as_deref() == Some(agent.id.as_str()) && t.status == TaskStatus::Running)
            .collect();
        let Some(median) = median(&durations) else { continue };
        for task in running {
            let elapsed = (i.now - task.started_at).num_seconds();
            if elapsed > (median * LONG_TASK_FACTOR).max(LONG_TASK_MIN_SECONDS) {
                out.push(Alert {
                    id: format!("long-task-{}", task.id),
                    level: AlertLevel::Warning,
                    title: "Tâche anormalement longue".into(),
                    detail: format!(
                        "{} — {} min écoulées, médiane de l'agent : {} min",
                        task.title,
                        elapsed / 60,
                        median / 60
                    ),
                    created_at: i.now,
                    acknowledged: false,
                    action_label: None,
                });
            }
        }
    }
    out
}

fn failure_alerts(i: &AlertInputs) -> Vec<Alert> {
    let since = i.now - Duration::minutes(FAILURE_WINDOW_MINUTES);
    let recent: Vec<_> = i
        .snapshot
        .tasks
        .iter()
        .filter(|t| t.status == TaskStatus::Failed && t.started_at >= since)
        .collect();
    if recent.len() < FAILURE_THRESHOLD {
        return vec![];
    }
    vec![Alert {
        id: "repeated-failures".into(),
        level: AlertLevel::Critical,
        title: "Échecs répétés".into(),
        detail: format!(
            "{} tâches en erreur sur les {} dernières minutes",
            recent.len(),
            FAILURE_WINDOW_MINUTES
        ),
        created_at: i.now,
        acknowledged: false,
        action_label: Some("Voir les tâches".into()),
    }]
}

fn provider_down_alerts(i: &AlertInputs) -> Vec<Alert> {
    i.snapshot
        .providers
        .iter()
        .filter(|p| matches!(p.availability, Availability::Unavailable))
        .map(|p| Alert {
            id: format!("provider-down-{}", p.id),
            level: AlertLevel::Warning,
            title: format!("{} indisponible", p.name),
            detail: p
                .note
                .clone()
                .unwrap_or_else(|| "Aucune réponse exploitable du provider".into()),
            created_at: i.now,
            acknowledged: false,
            action_label: None,
        })
        .collect()
}

fn median(values: &[i64]) -> Option<i64> {
    if values.is_empty() {
        return None;
    }
    let mut v = values.to_vec();
    v.sort_unstable();
    Some(v[v.len() / 2])
}

/// Compte les projets actifs : utilisé par les écrans et les tests.
pub fn active_projects(snapshot: &Snapshot) -> usize {
    snapshot
        .projects
        .iter()
        .filter(|p| p.status == ProjectStatus::Active)
        .count()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::*;
    use crate::money::{CostValue, Usd};
    use chrono::TimeZone;

    fn now() -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 11, 18, 12, 0, 0).unwrap()
    }

    fn snapshot() -> Snapshot {
        Snapshot {
            generated_at: now(),
            kpis: vec![],
            agents: vec![],
            timeline: vec![],
            alerts: vec![],
            providers: vec![],
            tasks: vec![],
            software: vec![],
            projects: vec![],
        }
    }

    fn task(id: &str, agent: &str, status: TaskStatus, minutes_ago: i64, duration_min: i64) -> TaskItem {
        let started = now() - Duration::minutes(minutes_ago);
        TaskItem {
            id: id.into(),
            title: format!("Tâche {id}"),
            project_id: None,
            project_name: None,
            agent_id: Some(agent.into()),
            agent_name: Some(agent.into()),
            provider: Some("openrouter".into()),
            model: Some("deepseek".into()),
            status,
            started_at: started,
            ended_at: if duration_min > 0 { Some(started + Duration::minutes(duration_min)) } else { None },
            tokens: TokenCounts::default(),
            cost: CostValue::unavailable("test"),
            error: None,
        }
    }

    #[test]
    fn no_alert_below_80_percent() {
        let s = snapshot();
        let alerts = evaluate(&AlertInputs { snapshot: &s, monthly_budget: Some(300.0), month_spent: 120.0, now: now() });
        assert!(alerts.is_empty(), "aucune alerte attendue: {alerts:?}");
    }

    #[test]
    fn budget_thresholds_are_escalating_and_unique() {
        let s = snapshot();
        for (spent, level) in [(245.0, AlertLevel::Info), (275.0, AlertLevel::Warning), (310.0, AlertLevel::Critical)] {
            let alerts = evaluate(&AlertInputs { snapshot: &s, monthly_budget: Some(300.0), month_spent: spent, now: now() });
            let budget: Vec<_> = alerts.iter().filter(|a| a.id.starts_with("budget-")).collect();
            assert_eq!(budget.len(), 1, "une seule alerte de budget");
            assert_eq!(budget[0].level, level);
        }
    }

    #[test]
    fn low_balance_only_when_a_real_amount_exists() {
        let mut s = snapshot();
        s.providers.push(Provider {
            id: "p1".into(), name: "OpenRouter".into(), kind: ProviderKind::Api,
            availability: Availability::Available, active_model: None,
            cost_today: CostValue::unavailable("x"),
            balance: CostValue::real(Usd::new(8.0), "API"),
            balance_alert_pct: 20, keychain_ref: None, note: None,
        });
        s.providers.push(Provider {
            id: "p2".into(), name: "Abliteration".into(), kind: ProviderKind::Api,
            availability: Availability::Available, active_model: None,
            cost_today: CostValue::unavailable("x"),
            balance: CostValue::unavailable("pas d'API"),
            balance_alert_pct: 20, keychain_ref: None, note: None,
        });
        let alerts = evaluate(&AlertInputs { snapshot: &s, monthly_budget: None, month_spent: 0.0, now: now() });
        assert_eq!(alerts.iter().filter(|a| a.id.starts_with("balance-")).count(), 1);
        assert!(alerts.iter().any(|a| a.id == "balance-p1"));
        assert!(!alerts.iter().any(|a| a.id == "balance-p2"), "pas d'alerte sans montant réel");
    }

    #[test]
    fn long_task_uses_agent_median() {
        let mut s = snapshot();
        s.agents.push(Agent {
            id: "a1".into(), name: "Hermès".into(), kind: AgentKind::Orchestrator, status: AgentStatus::Active,
            parent_id: None, provider: None, model: None, current_task_id: None,
            color_key: "accent/blue".into(), started_at: None,
        });
        for i in 0..3 {
            s.tasks.push(task(&format!("t{i}"), "a1", TaskStatus::Completed, 200, 2));
        }
        s.tasks.push(task("long", "a1", TaskStatus::Running, 45, 0));
        let alerts = evaluate(&AlertInputs { snapshot: &s, monthly_budget: None, month_spent: 0.0, now: now() });
        assert!(alerts.iter().any(|a| a.id == "long-task-long"));
    }

    #[test]
    fn repeated_failures_trigger_once() {
        let mut s = snapshot();
        for i in 0..3 {
            s.tasks.push(task(&format!("f{i}"), "a1", TaskStatus::Failed, 5, 1));
        }
        let alerts = evaluate(&AlertInputs { snapshot: &s, monthly_budget: None, month_spent: 0.0, now: now() });
        assert_eq!(alerts.iter().filter(|a| a.id == "repeated-failures").count(), 1);
    }

    #[test]
    fn unavailable_provider_is_reported() {
        let mut s = snapshot();
        s.providers.push(Provider {
            id: "p3".into(), name: "DeepSeek".into(), kind: ProviderKind::Api,
            availability: Availability::Unavailable, active_model: None,
            cost_today: CostValue::unavailable("x"), balance: CostValue::unavailable("x"),
            balance_alert_pct: 0, keychain_ref: None, note: Some("timeout".into()),
        });
        let alerts = evaluate(&AlertInputs { snapshot: &s, monthly_budget: None, month_spent: 0.0, now: now() });
        assert!(alerts.iter().any(|a| a.id == "provider-down-p3"));
    }
}

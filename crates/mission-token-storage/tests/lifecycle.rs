use chrono::{Duration, Utc};
use mission_token_storage::{seed, Db, TRASH_RETENTION_DAYS};

#[test]
fn settings_round_trip() {
    let db = Db::open_in_memory().unwrap();
    db.save_settings(Some(450.0), 85, 97, true).unwrap();
    assert_eq!(db.monthly_budget().unwrap(), Some(450.0));
    assert_eq!(db.setting("budget.alert.pct").unwrap().as_deref(), Some("85"));
    assert_eq!(db.setting("ui.hideDockIcon").unwrap().as_deref(), Some("true"));
}

#[test]
fn trash_is_reversible_then_purged_after_thirty_days() {
    let db = Db::open_in_memory().unwrap();
    seed::demo(&db).unwrap();
    let purge_at = db.trash_project("prj_free").unwrap();
    assert!(purge_at > Utc::now() + Duration::days(TRASH_RETENTION_DAYS - 1));

    // dans la fenêtre de rétention : rien n'est purgé
    assert_eq!(db.sweep_trash(Utc::now()).unwrap(), 0);
    assert!(db.projects(None).unwrap().iter().any(|p| p.id == "prj_free"));

    // restaurer sort de la corbeille
    db.restore_project("prj_free").unwrap();
    assert!(db.projects(None).unwrap().iter().any(|p| p.id == "prj_free" && p.status == mission_token_core::ProjectStatus::Active));

    // après expiration : purge des données internes uniquement
    db.trash_project("prj_free").unwrap();
    let later = Utc::now() + Duration::days(TRASH_RETENTION_DAYS + 1);
    assert_eq!(db.sweep_trash(later).unwrap(), 1);
    assert!(!db.projects(None).unwrap().iter().any(|p| p.id == "prj_free"));
}

#[test]
fn alerts_are_evaluated_and_not_duplicated() {
    let db = Db::open_in_memory().unwrap();
    seed::demo(&db).unwrap();
    // Budget calé sur la dépense réelle du mois : on teste le seuil, pas une valeur en dur.
    let spent = db.month_spent(Utc::now());
    assert!(spent > 0.0, "le jeu de démonstration doit produire un coût connu");
    db.save_settings(Some(spent * 0.9), 80, 95, false).unwrap();
    let snap = db.load_snapshot().unwrap();
    let budget_alert = snap.alerts.iter().find(|a| a.id.starts_with("budget-"));
    assert!(budget_alert.is_some(), "alertes: {:?}", snap.alerts.iter().map(|a| &a.id).collect::<Vec<_>>());
    let ids: Vec<_> = snap.alerts.iter().map(|a| a.id.clone()).collect();
    let mut dedup = ids.clone();
    dedup.sort();
    dedup.dedup();
    assert_eq!(ids.len(), dedup.len(), "aucune alerte dupliquée");
}

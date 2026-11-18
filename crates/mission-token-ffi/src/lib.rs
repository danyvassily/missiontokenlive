//! Pont C entre le moteur Rust et l'interface SwiftUI.
//!
//! Contrat minimal et stable (voir `include/mission_token.h`) :
//! - `mtl_version()`                       : version du moteur ;
//! - `mtl_snapshot_json(path)`             : instantané complet en JSON (UTF-8) ;
//! - `mtl_seed_demo(path)`                 : remplit la base avec les fixtures de démo ;
//! - `mtl_free_string(ptr)`                : libère toute chaîne renvoyée par la FFI.
//!
//! Règle : toute chaîne renvoyée est allouée par Rust et doit être libérée par
//! `mtl_free_string`. Aucune exception ne traverse la frontière FFI.

pub mod brain;
pub mod keys;
pub mod worktree;

use std::ffi::{c_char, CStr, CString};

fn to_c_string(s: String) -> *mut c_char {
    match CString::new(s) {
        Ok(c) => c.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

unsafe fn cstr_arg(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    CStr::from_ptr(ptr).to_str().ok().map(|s| s.to_string())
}

#[no_mangle]
pub extern "C" fn mtl_version() -> *mut c_char {
    to_c_string(format!(
        "MissionTokenLive core {} (protocole {})",
        mission_token_core::crate_version(),
        mission_token_core::PROTOCOL_VERSION
    ))
}

#[no_mangle]
pub extern "C" fn mtl_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            drop(CString::from_raw(ptr));
        }
    }
}

#[no_mangle]
pub extern "C" fn mtl_seed_demo(db_path: *const c_char) -> i32 {
    let Some(path) = (unsafe { cstr_arg(db_path) }) else { return -1 };
    match mission_token_storage::Db::open(&path) {
        Ok(db) => match mission_token_storage::seed::demo(&db) {
            Ok(()) => 0,
            Err(e) => {
                eprintln!("[mtl] seed demo failed: {e}");
                -3
            }
        },
        Err(e) => {
            eprintln!("[mtl] open failed: {e}");
            -2
        }
    }
}

/// Instantané JSON de l'application. `NULL` en cas d'erreur (jamais de panic).
#[no_mangle]
pub extern "C" fn mtl_snapshot_json(db_path: *const c_char) -> *mut c_char {
    let Some(path) = (unsafe { cstr_arg(db_path) }) else { return std::ptr::null_mut() };
    let result = std::panic::catch_unwind(|| {
        let db = mission_token_storage::Db::open(&path).ok()?;
        let snapshot = db.load_snapshot().ok()?;
        serde_json::to_string(&snapshot).ok()
    });
    match result {
        Ok(Some(json)) => to_c_string(json),
        _ => std::ptr::null_mut(),
    }
}

/// Collecte en lecture seule depuis Hermès : renvoie un tableau JSON de tâches.
#[no_mangle]
pub extern "C" fn mtl_hermes_tasks_json(limit: u32) -> *mut c_char {
    let result = std::panic::catch_unwind(|| {
        let adapter = mission_token_collectors::HermesAdapter::new(None);
        let tasks = adapter.recent_tasks(limit as usize).ok()?;
        serde_json::to_string(&tasks).ok()
    });
    match result {
        Ok(Some(json)) => to_c_string(json),
        _ => std::ptr::null_mut(),
    }
}

/// Présence des logiciels (ouvert / fermé), sans lecture de contenu.
#[no_mangle]
pub extern "C" fn mtl_desktop_activity_json() -> *mut c_char {
    let apps = mission_token_collectors::DesktopActivityAdapter::detect();
    match serde_json::to_string(&apps) {
        Ok(json) => to_c_string(json),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Cycle de vie d'un projet : `archive`, `restore`, `trash`, `purge`.
///
/// N'agit que sur la base interne de MissionTokenLive. Aucun accès à un dossier, un
/// dépôt ou une tâche externe.
#[no_mangle]
pub extern "C" fn mtl_project_action(
    db_path: *const c_char,
    project_id: *const c_char,
    action: *const c_char,
) -> i32 {
    let (Some(path), Some(id), Some(act)) = (unsafe { cstr_arg(db_path) }, unsafe { cstr_arg(project_id) }, unsafe { cstr_arg(action) }) else {
        return -1;
    };
    let Ok(db) = mission_token_storage::Db::open(&path) else { return -2 };
    let res = match act.as_str() {
        "archive" => db.archive_project(&id),
        "restore" => db.restore_project(&id),
        "trash" => db.trash_project(&id).map(|_| ()),
        "purge" => db.purge_project(&id),
        _ => return -4,
    };
    match res {
        Ok(()) => 0,
        Err(_) => -3,
    }
}

/// État du cerveau gbrain en JSON (lecture seule).
#[no_mangle]
pub extern "C" fn mtl_brain_json() -> *mut c_char {
    let stats = brain::read_stats(None);
    match serde_json::to_string(&stats) {
        Ok(json) => to_c_string(json),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Purge les projets dont la corbeille a expiré (30 jours). Renvoie le nombre purgé, ou -1.
#[no_mangle]
pub extern "C" fn mtl_sweep_trash(db_path: *const c_char) -> i32 {
    let Some(path) = (unsafe { cstr_arg(db_path) }) else { return -1 };
    let Ok(db) = mission_token_storage::Db::open(&path) else { return -1 };
    match db.sweep_trash(chrono::Utc::now()) {
        Ok(n) => n as i32,
        Err(_) => -1,
    }
}

/// Réglages courants en JSON (`budget`, `warn`, `critical`, `hideDock`). NULL si indisponible.
#[no_mangle]
pub extern "C" fn mtl_settings_json(db_path: *const c_char) -> *mut c_char {
    let Some(path) = (unsafe { cstr_arg(db_path) }) else { return std::ptr::null_mut() };
    let Ok(db) = mission_token_storage::Db::open(&path) else { return std::ptr::null_mut() };
    let budget = db.monthly_budget().ok().flatten();
    let warn = db.setting("budget.alert.pct").ok().flatten().and_then(|v| v.parse::<i32>().ok()).unwrap_or(80);
    let critical = db.setting("budget.critical.pct").ok().flatten().and_then(|v| v.parse::<i32>().ok()).unwrap_or(95);
    let hide_dock = db.setting("ui.hideDockIcon").ok().flatten().map(|v| v == "true").unwrap_or(false);
    let json = serde_json::json!({
        "budget": budget,
        "warn": warn,
        "critical": critical,
        "hideDock": hide_dock,
    });
    to_c_string(json.to_string())
}

/// Enregistre les réglages. `budget` vide = pas de budget défini. 0 = succès.
#[no_mangle]
pub extern "C" fn mtl_save_settings(
    db_path: *const c_char,
    budget: *const c_char,
    warn: i32,
    critical: i32,
    hide_dock: i32,
) -> i32 {
    let Some(path) = (unsafe { cstr_arg(db_path) }) else { return -1 };
    let budget_value = unsafe { cstr_arg(budget) }
        .and_then(|v| v.trim().replace(',', ".").parse::<f64>().ok());
    let Ok(db) = mission_token_storage::Db::open(&path) else { return -1 };
    match db.save_settings(
        budget_value,
        warn.clamp(1, 100) as u8,
        critical.clamp(1, 100) as u8,
        hide_dock != 0,
    ) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

#[cfg(test)]
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_is_returned_and_freeable() {
        let p = mtl_version();
        assert!(!p.is_null());
        let s = unsafe { CStr::from_ptr(p).to_str().unwrap().to_string() };
        assert!(s.contains("MissionTokenLive core"));
        mtl_free_string(p);
    }

    #[test]
    fn project_lifecycle_is_local_and_reversible() {
        let dir = tempfile::tempdir().unwrap();
        let db = dir.path().join("mtl.db");
        let c = CString::new(db.to_str().unwrap()).unwrap();
        assert_eq!(mtl_seed_demo(c.as_ptr()), 0);

        let id = CString::new("prj_agorax").unwrap();
        let act = CString::new("archive").unwrap();
        assert_eq!(mtl_project_action(c.as_ptr(), id.as_ptr(), act.as_ptr()), 0);

        let p = mtl_snapshot_json(c.as_ptr());
        let json = unsafe { CStr::from_ptr(p).to_str().unwrap().to_string() };
        mtl_free_string(p);
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        let proj = v["projects"].as_array().unwrap().iter()
            .find(|p| p["id"] == "prj_agorax").unwrap();
        assert_eq!(proj["status"], "archived");
    }

    #[test]
    fn settings_round_trip_through_ffi() {
        let dir = tempfile::tempdir().unwrap();
        let db = dir.path().join("mtl.db");
        let c = CString::new(db.to_str().unwrap()).unwrap();
        assert_eq!(mtl_seed_demo(c.as_ptr()), 0);
        let budget = CString::new("450,50").unwrap();
        assert_eq!(mtl_save_settings(c.as_ptr(), budget.as_ptr(), 85, 97, 1), 0);
        let p = mtl_settings_json(c.as_ptr());
        assert!(!p.is_null());
        let json = unsafe { CStr::from_ptr(p).to_str().unwrap().to_string() };
        mtl_free_string(p);
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(v["warn"], 85);
        assert_eq!(v["critical"], 97);
        assert_eq!(v["hideDock"], true);
        assert!((v["budget"].as_f64().unwrap() - 450.50).abs() < 1e-9);
    }

    #[test]
    fn null_path_returns_null() {
        assert!(mtl_snapshot_json(std::ptr::null()).is_null());
    }

    #[test]
    fn demo_snapshot_round_trips_through_ffi() {
        let dir = tempfile::tempdir().unwrap();
        let db = dir.path().join("mtl.db");
        let c = CString::new(db.to_str().unwrap()).unwrap();
        assert_eq!(mtl_seed_demo(c.as_ptr()), 0);
        let p = mtl_snapshot_json(c.as_ptr());
        assert!(!p.is_null());
        let json = unsafe { CStr::from_ptr(p).to_str().unwrap().to_string() };
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert!(v["agents"].as_array().unwrap().len() >= 5);
        assert!(v["tasks"].as_array().unwrap().len() >= 9);
        assert!(v["kpis"].as_array().unwrap().iter().any(|k| k["key"] == "cost_today"));
        mtl_free_string(p);
    }
}


//! Arborescence de travail réelle, lue dans la base d'Hermès.
//!
//! Aucun contenu de message n'est lu : uniquement des titres de session, des noms d'outils,
//! des objectifs de délégation et des noms de processus. C'est ce qui alimente la vue 3D.

use rusqlite::{Connection, OpenFlags};
use serde::Serialize;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkTool {
    pub name: String,
    pub count: i64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkDelegation {
    pub id: String,
    pub goal: String,
    pub state: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkBranch {
    pub id: String,
    pub title: String,
    pub project: String,
    pub state: String,
    pub messages: i64,
    pub tools: Vec<WorkTool>,
    pub delegations: Vec<WorkDelegation>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkHarness {
    pub name: String,
    pub detail: String,
    pub active: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkTree {
    pub available: bool,
    pub root_label: String,
    pub running_tasks: i64,
    pub active_sessions: i64,
    pub branches: Vec<WorkBranch>,
    pub harnesses: Vec<WorkHarness>,
}

fn home() -> String {
    std::env::var("HOME").unwrap_or_else(|_| "/Users/danyvassily".into())
}

fn short_title(title: &str) -> String {
    let t = title.trim();
    let cleaned = if t.starts_with("@file:") { "Session technique" } else { t };
    let mut out: String = cleaned.chars().take(70).collect();
    if cleaned.chars().count() > 70 {
        out.push('…');
    }
    out
}

fn project_of(cwd: &str) -> String {
    cwd.trim_end_matches('/')
        .rsplit('/')
        .next()
        .unwrap_or("~")
        .to_string()
}

/// Harnais externes détectés par leurs processus : on ne devine pas, on regarde.
fn harnesses() -> Vec<WorkHarness> {
    let patterns = [
        ("OpenCode", "opencode"),
        ("Gemini CLI", "gemini"),
        ("Antigravity", "agy-code"),
        ("Antigravity", "antigravity"),
        ("Codex", "codex"),
    ];
    let ps = std::process::Command::new("ps")
        .args(["-axo", "pid=,command="])
        .output()
        .ok()
        .map(|o| String::from_utf8_lossy(&o.stdout).to_string())
        .unwrap_or_default();
    let mut out: Vec<WorkHarness> = vec![];
    for (name, needle) in patterns {
        if out.iter().any(|h| h.name == name) {
            continue;
        }
        let hit = ps.lines().find(|l| {
            let low = l.to_lowercase();
            low.contains(needle) && !low.contains("hermes") && !low.contains("grep")
        });
        out.push(WorkHarness {
            name: name.to_string(),
            detail: hit.map(|l| l.chars().take(90).collect::<String>()).unwrap_or_else(|| "aucun processus".into()),
            active: hit.is_some(),
        });
    }
    out
}

pub fn build(db_path: &str) -> WorkTree {
    let mut tree = WorkTree {
        available: false,
        root_label: "Hermès".into(),
        running_tasks: 0,
        active_sessions: 0,
        branches: vec![],
        harnesses: harnesses(),
    };
    let Ok(conn) = Connection::open_with_flags(db_path, OpenFlags::SQLITE_OPEN_READ_ONLY) else {
        return tree;
    };
    tree.available = true;

    let cutoff = now_epoch() - 7.0 * 86400.0;
    let mut stmt = match conn.prepare(
        "SELECT id, COALESCE(title,''), COALESCE(cwd,''), COALESCE(message_count,0), COALESCE(last_activity_at, started_at)
         FROM sessions
         WHERE COALESCE(last_activity_at, started_at) >= ?
         ORDER BY COALESCE(last_activity_at, started_at) DESC
         LIMIT 7",
    ) {
        Ok(s) => s,
        Err(_) => return tree,
    };
    let rows: Vec<(String, String, String, i64, f64)> = stmt
        .query_map([cutoff], |r| {
            Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get::<_, f64>(4).unwrap_or(0.0)))
        })
        .map(|it| it.flatten().collect())
        .unwrap_or_default();

    let now = now_epoch();
    for (id, title, cwd, messages, last) in rows {
        let active = (now - last) < 900.0; // 15 minutes
        let mut tools: Vec<WorkTool> = vec![];
        if let Ok(mut t) = conn.prepare(
            "SELECT tool_name, COUNT(*) FROM messages
             WHERE session_id = ? AND tool_name IS NOT NULL
             GROUP BY tool_name ORDER BY COUNT(*) DESC LIMIT 3",
        ) {
            if let Ok(iter) = t.query_map([&id], |r| {
                Ok(WorkTool { name: r.get(0)?, count: r.get(1)? })
            }) {
                tools = iter.flatten().collect();
            }
        }
        let mut delegations: Vec<WorkDelegation> = vec![];
        if let Ok(mut t) = conn.prepare(
            "SELECT delegation_id, COALESCE(task_json,''), COALESCE(state,'')
             FROM async_delegations WHERE parent_session_id = ? OR origin_session LIKE ?
             ORDER BY rowid DESC LIMIT 3",
        ) {
            if let Ok(iter) = t.query_map([&id, &format!("%{}%", id)], |r| {
                let raw: String = r.get(1)?;
                let goal = extract_goal(&raw);
                Ok(WorkDelegation { id: r.get(0)?, goal, state: r.get(2)? })
            }) {
                delegations = iter.flatten().collect();
            }
        }
        if active {
            tree.active_sessions += 1;
        }
        tree.branches.push(WorkBranch {
            id,
            title: short_title(&title),
            project: project_of(&cwd),
            state: if active { "active".into() } else { "idle".into() },
            messages,
            tools,
            delegations,
        });
    }

    if let Ok(mut t) = conn.prepare("SELECT COUNT(*) FROM tasks WHERE status='running'") {
        tree.running_tasks = t.query_row([], |r| r.get::<_, i64>(0)).unwrap_or(0);
    }
    tree
}

/// Extrait `"goal": "..."` du JSON de délégation sans dépendre de sa structure complète.
fn extract_goal(raw: &str) -> String {
    if let Ok(v) = serde_json::from_str::<serde_json::Value>(raw) {
        if let Some(g) = v.get("goal").and_then(|x| x.as_str()) {
            let mut out: String = g.chars().take(80).collect();
            if g.chars().count() > 80 {
                out.push('…');
            }
            return out;
        }
    }
    String::from("délégation")
}

fn now_epoch() -> f64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0)
}

#[no_mangle]
pub unsafe extern "C" fn mtl_worktree_json(db_path: *const c_char) -> *mut c_char {
    if db_path.is_null() {
        return std::ptr::null_mut();
    }
    let Ok(path) = CStr::from_ptr(db_path).to_str() else { return std::ptr::null_mut() };
    let tree = build(path);
    match serde_json::to_string(&tree) {
        Ok(s) => CString::new(s).map(|c| c.into_raw()).unwrap_or(std::ptr::null_mut()),
        Err(_) => std::ptr::null_mut(),
    }
}

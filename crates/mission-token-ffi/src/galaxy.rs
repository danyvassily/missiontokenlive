
//! « Galaxie » de gbrain : agrégat de ce que le cerveau contient réellement.
//!
//! Lecture seule de `~/.gbrain/gbrain.sqlite`. On ne renvoie jamais le texte intégral :
//! les faits sont tronqués à 70 caractères, et seuls un échantillon et des compteurs sortent.
//! Aucun secret ne peut passer : la base a été écrite après redaction.

use rusqlite::{Connection, OpenFlags};
use serde::Serialize;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GNode {
    pub id: String,
    pub label: String,
    pub kind: String,
    pub weight: i64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GEdge {
    pub a: usize,
    pub b: usize,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GContact {
    pub name: String,
    pub messages: i64,
    pub relation: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Galaxy {
    pub available: bool,
    pub facts: i64,
    pub sources: i64,
    pub entities: i64,
    pub nodes: Vec<GNode>,
    pub edges: Vec<GEdge>,
    pub contacts: Vec<GContact>,
}

fn home() -> String {
    std::env::var("HOME").unwrap_or_else(|_| "/Users/danyvassily".into())
}

fn short(text: &str, max: usize) -> String {
    let clean = text.split_whitespace().collect::<Vec<_>>().join(" ");
    if clean.chars().count() <= max {
        return clean;
    }
    let mut out: String = clean.chars().take(max).collect();
    out.push('…');
    out
}

fn basename(path: &str) -> String {
    path.rsplit('/').next().unwrap_or(path).to_string()
}

/// Compteurs de messages par contact, lus dans la base WhatsApp locale (si présente).
fn whatsapp_counts() -> Vec<(String, i64)> {
    let path = format!("{}/.gbrain/wa.sqlite", home());
    let Ok(conn) = Connection::open_with_flags(&path, OpenFlags::SQLITE_OPEN_READ_ONLY) else {
        return vec![];
    };
    let mut out = vec![];
    if let Ok(mut stmt) = conn.prepare(
        "SELECT contact, COUNT(*) FROM messages GROUP BY contact ORDER BY COUNT(*) DESC",
    ) {
        if let Ok(rows) = stmt.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?))) {
            out = rows.flatten().collect();
        }
    }
    out
}

pub fn build(db_path: &str) -> Galaxy {
    let mut galaxy = Galaxy {
        available: false,
        facts: 0,
        sources: 0,
        entities: 0,
        nodes: vec![],
        edges: vec![],
        contacts: vec![],
    };
    let Ok(conn) = Connection::open_with_flags(db_path, OpenFlags::SQLITE_OPEN_READ_ONLY) else {
        return galaxy;
    };
    let modern = conn.prepare("SELECT status FROM facts LIMIT 0").is_ok();
    let view = if modern { "CREATE TEMP VIEW current_facts AS SELECT * FROM facts WHERE status='active'" }
               else { "CREATE TEMP VIEW current_facts AS SELECT * FROM facts" };
    if conn.execute_batch(view).is_err() { return galaxy; }
    galaxy.available = true;

    let count = |sql: &str| -> i64 {
        conn.query_row(sql, [], |r| r.get::<_, i64>(0)).unwrap_or(0)
    };
    galaxy.facts = count("SELECT COUNT(*) FROM current_facts");
    galaxy.sources = count("SELECT COUNT(*) FROM sources");
    galaxy.entities = count(
        "SELECT COUNT(DISTINCT entity) FROM current_facts WHERE entity IS NOT NULL AND entity <> ''",
    );

    // Source 0 : gbrain lui-même, le centre de la galaxie.
    galaxy.nodes.push(GNode {
        id: "core".into(),
        label: "gbrain".into(),
        kind: "core".into(),
        weight: galaxy.facts,
    });

    // Couche 1 : sources, groupées par type pour rester lisible.
    let mut source_index: Vec<(String, usize)> = vec![];
    if let Ok(mut stmt) = conn.prepare(
        "SELECT kind, COUNT(*) c FROM sources GROUP BY kind ORDER BY c DESC",
    ) {
        if let Ok(rows) = stmt.query_map([], |r| {
            Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?))
        }) {
            for (kind, c) in rows.flatten() {
                let idx = galaxy.nodes.len();
                galaxy.nodes.push(GNode {
                    id: format!("src-{kind}"),
                    label: format!("{} ({})", kind, c),
                    kind: "source".into(),
                    weight: c,
                });
                galaxy.edges.push(GEdge { a: 0, b: idx });
                source_index.push((kind, idx));
            }
        }
    }

    // Contacts WhatsApp : ce sont des entités, mais on veut les compter en messages
    // et non en faits — et surtout ne pas déverser 3 380 points dans le nuage.
    let wa_counts = whatsapp_counts();
    let mut contacts: Vec<String> = vec![];

    // Couche 2 : entités les plus citées.
    let mut entity_index: Vec<(String, usize)> = vec![];
    if let Ok(mut stmt) = conn.prepare(
        "SELECT entity, COUNT(*) c FROM current_facts WHERE entity IS NOT NULL AND entity <> ''
         GROUP BY entity ORDER BY c DESC LIMIT 28",
    ) {
        if let Ok(rows) = stmt.query_map([], |r| {
            Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?))
        }) {
            for (entity, c) in rows.flatten() {
                let messages = wa_counts.iter()
                    .find(|(name, _)| name.eq_ignore_ascii_case(&entity))
                    .map(|(_, n)| *n);
                let is_contact = messages.is_some();
                if is_contact {
                    contacts.push(entity.clone());
                }
                let idx = galaxy.nodes.len();
                galaxy.nodes.push(GNode {
                    id: format!("ent-{entity}"),
                    label: short(&entity, 26),
                    kind: if is_contact { "contact".into() } else { "entity".into() },
                    weight: messages.unwrap_or(c),
                });
                galaxy.edges.push(GEdge { a: 0, b: idx });
                entity_index.push((entity, idx));
            }
        }
    }

    // Couche 3 : échantillon de faits, reliés à leur entité et à leur source.
    if let Ok(mut stmt) = conn.prepare(
        "SELECT f.text, f.entity, s.kind FROM current_facts f JOIN sources s ON s.id = f.source_id
         ORDER BY f.id DESC LIMIT 260",
    ) {
        if let Ok(rows) = stmt.query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, Option<String>>(1)?,
                r.get::<_, String>(2)?,
            ))
        }) {
            for (text, entity, src_kind) in rows.flatten() {
                if let Some(name) = &entity {
                    if contacts.iter().any(|c| c.eq_ignore_ascii_case(name)) {
                        continue;   // agrégé dans le contact : pas de point par fait
                    }
                }
                let idx = galaxy.nodes.len();
                galaxy.nodes.push(GNode {
                    id: format!("fact-{idx}"),
                    label: short(&text, 70),
                    kind: "fact".into(),
                    weight: 1,
                });
                if let Some(entity) = entity {
                    if let Some((_, target)) = entity_index.iter().find(|(e, _)| *e == entity) {
                        galaxy.edges.push(GEdge { a: idx, b: *target });
                    }
                }
                if let Some((_, target)) = source_index.iter().find(|(k, _)| *k == src_kind) {
                    galaxy.edges.push(GEdge { a: idx, b: *target });
                }
            }
        }
    }

    // Fiches contacts : ce que le modèle a retenu, sans les conversations.
    if let Ok(mut stmt) = conn.prepare(
        "SELECT text, entity FROM current_facts WHERE text LIKE 'Contact WhatsApp %' ORDER BY id DESC",
    ) {
        if let Ok(rows) = stmt.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, Option<String>>(1)?))) {
            for (text, entity) in rows.flatten() {
                let name = entity.unwrap_or_else(|| "contact".into());
                let relation = text
                    .split_once(" : ")
                    .map(|(_, rest)| rest.to_string())
                    .unwrap_or_default();
                let messages = wa_counts.iter()
                    .find(|(c, _)| c.eq_ignore_ascii_case(&name))
                    .map(|(_, n)| *n)
                    .unwrap_or(0);
                galaxy.contacts.push(GContact {
                    name,
                    messages,
                    relation: short(&relation, 90),
                });
            }
        }
    }
    galaxy.contacts.sort_by(|a, b| b.messages.cmp(&a.messages));

    galaxy
}

#[no_mangle]
pub unsafe extern "C" fn mtl_galaxy_json(db_path: *const c_char) -> *mut c_char {
    if db_path.is_null() {
        return std::ptr::null_mut();
    }
    let Ok(path) = CStr::from_ptr(db_path).to_str() else {
        return std::ptr::null_mut();
    };
    match serde_json::to_string(&build(path)) {
        Ok(s) => CString::new(s).map(|c| c.into_raw()).unwrap_or(std::ptr::null_mut()),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Chemin par défaut de la base gbrain, pour que l'app n'ait pas à le devine.
#[no_mangle]
pub extern "C" fn mtl_galaxy_default_path() -> *mut c_char {
    let path = format!("{}/.gbrain/gbrain.sqlite", home());
    CString::new(path).map(|c| c.into_raw()).unwrap_or(std::ptr::null_mut())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn galaxy_reads_real_brain_if_present() {
        let path = format!("{}/.gbrain/gbrain.sqlite", home());
        if !std::path::Path::new(&path).exists() {
            return;
        }
        let g = build(&path);
        assert!(g.available);
        assert!(g.facts > 0);
        assert!(g.nodes.len() > 20, "nœuds: {}", g.nodes.len());
        assert!(g.edges.len() > 20, "arêtes: {}", g.edges.len());
        // le centre doit être le premier nœud, et aucune arête ne doit pointer hors bornes
        assert_eq!(g.nodes[0].kind, "core");
        for e in &g.edges {
            assert!(e.a < g.nodes.len() && e.b < g.nodes.len());
        }
        // les libellés de faits sont tronqués : jamais de texte brut long
        assert!(g.nodes.iter().filter(|n| n.kind == "fact")
            .all(|n| n.label.chars().count() <= 71));
    }
}

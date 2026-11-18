
//! Lecture en lecture seule du cerveau gbrain (`~/.gbrain/gbrain.sqlite`).
//!
//! Aucune écriture, aucune requête sur le contenu des conversations : uniquement des
//! compteurs, les entités les plus citées et les derniers faits, pour l'écran « Cerveau ».

use rusqlite::{Connection, OpenFlags};
use serde::Serialize;
use std::path::PathBuf;

#[derive(Serialize)]
pub struct BrainEntity {
    pub name: String,
    pub facts: i64,
}

#[derive(Serialize)]
pub struct BrainFact {
    pub text: String,
    pub kind: String,
    pub entity: Option<String>,
    pub source: Option<String>,
}

#[derive(Serialize)]
pub struct BrainStats {
    pub available: bool,
    pub path: String,
    pub facts: i64,
    pub chunks: i64,
    pub sources: i64,
    pub entities: i64,
    pub last_ingest: Option<String>,
    pub top_entities: Vec<BrainEntity>,
    pub recent: Vec<BrainFact>,
}

pub fn default_path() -> PathBuf {
    dirs_home().join(".gbrain").join("gbrain.sqlite")
}

fn dirs_home() -> PathBuf {
    std::env::var("HOME").map(PathBuf::from).unwrap_or_else(|_| PathBuf::from("/"))
}

pub fn read_stats(path: Option<PathBuf>) -> BrainStats {
    let path = path.unwrap_or_else(default_path);
    let shown = path.to_string_lossy().replace(&dirs_home().to_string_lossy().to_string(), "~");
    let mut out = BrainStats {
        available: false,
        path: shown,
        facts: 0,
        chunks: 0,
        sources: 0,
        entities: 0,
        last_ingest: None,
        top_entities: vec![],
        recent: vec![],
    };
    if !path.exists() {
        return out;
    }
    let Ok(conn) = Connection::open_with_flags(&path, OpenFlags::SQLITE_OPEN_READ_ONLY) else {
        return out;
    };
    out.available = true;

    let count = |table: &str| -> i64 {
        conn.query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |r| r.get::<_, i64>(0))
            .unwrap_or(0)
    };
    out.facts = count("facts");
    out.chunks = count("chunks");
    out.sources = count("sources");
    out.entities = conn
        .query_row("SELECT COUNT(DISTINCT entity) FROM facts WHERE entity IS NOT NULL", [], |r| r.get::<_, i64>(0))
        .unwrap_or(0);
    out.last_ingest = conn
        .query_row("SELECT MAX(ingested_at) FROM sources", [], |r| r.get::<_, Option<String>>(0))
        .ok()
        .flatten();

    if let Ok(mut st) = conn.prepare(
        "SELECT entity, COUNT(*) n FROM facts WHERE entity IS NOT NULL GROUP BY entity ORDER BY n DESC LIMIT 6",
    ) {
        if let Ok(rows) = st.query_map([], |r| {
            Ok(BrainEntity { name: r.get(0)?, facts: r.get(1)? })
        }) {
            out.top_entities = rows.flatten().collect();
        }
    }

    if let Ok(mut st) = conn.prepare(
        "SELECT f.text, f.kind, f.entity, s.path FROM facts f
         LEFT JOIN sources s ON s.id = f.source_id
         ORDER BY f.id DESC LIMIT 8",
    ) {
        if let Ok(rows) = st.query_map([], |r| {
            let raw: Option<String> = r.get(3)?;
            Ok(BrainFact {
                text: r.get(0)?,
                kind: r.get(1)?,
                entity: r.get(2)?,
                source: raw.map(|p| {
                    p.replace(&dirs_home().to_string_lossy().to_string(), "~")
                }),
            })
        }) {
            out.recent = rows.flatten().collect();
        }
    }
    out
}

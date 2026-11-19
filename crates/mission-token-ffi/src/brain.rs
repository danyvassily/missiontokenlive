
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
    pub at: Option<String>,
    pub status: String,
}

#[derive(Serialize)]
pub struct BrainSource {
    pub path: String,
    pub kind: String,
    pub facts: i64,
    pub present: bool,
    pub ingested_at: Option<String>,
    pub last_error: Option<String>,
}

#[derive(Serialize)]
pub struct BrainStats {
    pub available: bool,
    pub path: String,
    pub facts: i64,
    pub chunks: i64,
    #[serde(rename = "sourceCount")]
    pub source_count: i64,
    pub entities: i64,
    pub last_ingest: Option<String>,
    pub top_entities: Vec<BrainEntity>,
    pub recent: Vec<BrainFact>,
    #[serde(rename = "sourceList")]
    pub sources: Vec<BrainSource>,
    pub never: Vec<String>,
    pub pending: i64,
    pub superseded: i64,
    pub last_error: Option<String>,
}

/// Périmètre exclu, affiché tel quel dans l'interface : l'utilisateur doit pouvoir
/// vérifier ce que le cerveau ne lit pas, pas seulement ce qu'il lit.
const NEVER: &[&str] = &["Aucune capture d’écran, frappe clavier ou presse-papiers par gbrain"];

pub fn default_path() -> PathBuf {
    std::env::var("GBRAIN_DIR").map(PathBuf::from).unwrap_or_else(|_| dirs_home().join(".gbrain")).join("gbrain.sqlite")
}

fn dirs_home() -> PathBuf {
    std::env::var("HOME").map(PathBuf::from).unwrap_or_else(|_| PathBuf::from("/"))
}

/// Détecte les lignes de structure ou d'en-tête interne (notamment issues de `PEOPLE/*.md`)
/// qui polluent le flux de faits : citations `>`, titres Markdown, mentions « USAGE INTERNE »,
/// lignes de tableau vides ou sous-titres isolés se terminant par `:`.
pub fn is_polluting_fact(text: &str, source: Option<&str>) -> bool {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return true;
    }
    if trimmed.starts_with('>') || trimmed.starts_with('#') {
        return true;
    }
    let upper = trimmed.to_uppercase();
    if upper.contains("USAGE INTERNE") || upper.contains("NEED-TO-KNOW") || upper.starts_with("SOURCE=") {
        return true;
    }
    let is_people_source = source.map(|s| s.contains("PEOPLE/")).unwrap_or(false);
    if is_people_source {
        if trimmed.ends_with(':') && trimmed.chars().count() < 55 {
            return true;
        }
        if trimmed.starts_with('|') && trimmed.contains("---") {
            return true;
        }
    }
    false
}

pub fn read_stats(path: Option<PathBuf>) -> BrainStats {
    let path = path.unwrap_or_else(default_path);
    let home = dirs_home();
    let shown = path.to_string_lossy().replace(&home.to_string_lossy().to_string(), "~");
    let mut out = BrainStats {
        available: false, path: shown, facts: 0, chunks: 0, source_count: 0, entities: 0,
        last_ingest: None, top_entities: vec![], recent: vec![], sources: vec![],
        never: NEVER.iter().map(|s| s.to_string()).collect(), pending: 0, superseded: 0, last_error: None,
    };
    let Ok(conn) = Connection::open_with_flags(&path, OpenFlags::SQLITE_OPEN_READ_ONLY) else { return out; };
    if conn.query_row("SELECT COUNT(*) FROM facts", [], |r| r.get::<_,i64>(0)).is_err() { return out; }
    out.available = true;
    let modern = conn.prepare("SELECT status FROM facts LIMIT 0").is_ok();
    let active = if modern { " WHERE status='active'" } else { "" };
    let count = |sql: &str| conn.query_row(sql, [], |r| r.get::<_,i64>(0)).unwrap_or(0);
    out.facts = count(&format!("SELECT COUNT(*) FROM facts{active}"));
    out.chunks = count(&format!("SELECT COUNT(*) FROM chunks{active}"));
    out.pending = count("SELECT COUNT(*) FROM candidates WHERE status='pending'");
    if modern { out.superseded = count("SELECT COUNT(*) FROM facts WHERE status='superseded'"); }
    out.last_ingest = if modern {
        conn.query_row("SELECT v FROM meta WHERE k='last_ingest'", [], |r| r.get::<_,String>(0)).ok()
    } else {
        conn.query_row("SELECT MAX(ingested_at) FROM sources", [], |r| r.get::<_,Option<String>>(0)).ok().flatten()
    };
    let entity_filter = if modern { " AND status='active'" } else { "" };
    if let Ok(mut st) = conn.prepare(&format!("SELECT entity,COUNT(*) n FROM facts WHERE entity IS NOT NULL{entity_filter} GROUP BY entity ORDER BY n DESC")) {
        if let Ok(rows) = st.query_map([], |r| Ok(BrainEntity { name:r.get(0)?, facts:r.get(1)? })) { out.top_entities=rows.flatten().collect(); }
    }
    out.entities = out.top_entities.len() as i64;
    let fact_filter = if modern { " AND f.status='active'" } else { "" };
    let error_column = if modern { "s.last_error" } else { "NULL" };
    if let Ok(mut st) = conn.prepare(&format!("SELECT s.path,s.kind,COUNT(f.id),s.ingested_at,{error_column} FROM sources s LEFT JOIN facts f ON f.source_id=s.id{fact_filter} GROUP BY s.id ORDER BY COUNT(f.id) DESC")) {
        if let Ok(rows) = st.query_map([], |r| {
            let raw:String=r.get(0)?;
            let actual = if let Some(rel)=raw.strip_prefix("pdf:") {
                path.parent().unwrap_or(&home).join(rel)
            } else if raw.starts_with("wa:") { path.parent().unwrap_or(&home).join("wa.sqlite") }
            else if let Some(rel)=raw.strip_prefix("~/") { home.join(rel) }
            else { PathBuf::from(&raw) };
            Ok(BrainSource { path:raw.replace(&home.to_string_lossy().to_string(),"~"), kind:r.get(1)?, facts:r.get(2)?,
                present:raw.starts_with("gbrain:") || actual.exists(), ingested_at:r.get(3)?,last_error:r.get(4)? })
        }) { out.sources=rows.flatten().collect(); }
    }
    // Only add a configured root when none of its files is represented in the database.
    let config = path.parent().unwrap_or(&home).join("config.json");
    if let Ok(raw)=std::fs::read_to_string(config) {
        if let Ok(cfg)=serde_json::from_str::<serde_json::Value>(&raw) {
            if let Some(entries)=cfg.get("sources").and_then(|v|v.as_array()) {
                for entry in entries {
                    let Some(raw)=entry.get("path").and_then(|v|v.as_str()) else {continue};
                    let shown=raw.replace(&home.to_string_lossy().to_string(),"~");
                    let expanded=if let Some(rest)=raw.strip_prefix("~/") {home.join(rest)} else {PathBuf::from(raw)};
                    if !out.sources.iter().any(|s|s.path==shown || s.path.starts_with(&format!("{shown}/"))) {
                        out.sources.push(BrainSource {path:shown,kind:entry.get("kind").and_then(|v|v.as_str()).unwrap_or("memory").to_string(),facts:0,present:expanded.exists(),ingested_at:None,last_error:None});
                    }
                }
            }
        }
    }
    out.source_count=out.sources.len() as i64;
    out.last_error=out.sources.iter().find_map(|s|s.last_error.clone());
    let status_column = if modern {"f.status"} else {"'active'"};
    let condition=if modern {" WHERE f.status='active'"} else {""};
    if let Ok(mut st)=conn.prepare(&format!("SELECT f.text,f.kind,f.entity,s.path,f.created_at,{status_column} FROM facts f LEFT JOIN sources s ON s.id=f.source_id{condition} ORDER BY f.id DESC LIMIT 80")) {
        if let Ok(rows)=st.query_map([],|r| {
            let raw:Option<String>=r.get(3)?;
            Ok(BrainFact {text:r.get(0)?,kind:r.get(1)?,entity:r.get(2)?,source:raw.map(|p|p.replace(&home.to_string_lossy().to_string(),"~")),at:r.get(4)?,status:r.get(5)?})
        }) {out.recent=rows.flatten().filter(|f|!is_polluting_fact(&f.text,f.source.as_deref())).take(8).collect();}
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn active_counts_and_missing_sources_are_truthful() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("brain.sqlite");
        let conn = Connection::open(&path).unwrap();
        conn.execute_batch("CREATE TABLE facts(id INTEGER,text TEXT,kind TEXT,entity TEXT,source_id INTEGER,created_at TEXT,status TEXT);
          CREATE TABLE chunks(status TEXT); CREATE TABLE sources(id INTEGER,path TEXT,kind TEXT,ingested_at TEXT,last_error TEXT);
          CREATE TABLE candidates(status TEXT); CREATE TABLE meta(k TEXT,v TEXT);
          INSERT INTO sources VALUES(1,'/missing/source.md','memory',NULL,NULL);
          INSERT INTO facts VALUES(1,'Active information','memory','Alpha',1,NULL,'active');
          INSERT INTO facts VALUES(2,'Archived information','memory','Beta',1,NULL,'superseded');
          INSERT INTO candidates VALUES('pending');").unwrap();
        let stats = read_stats(Some(path));
        assert!(stats.available);
        assert_eq!(stats.facts, 1);
        assert_eq!(stats.superseded, 1);
        assert_eq!(stats.pending, 1);
        assert_eq!(stats.entities, 1);
        assert!(!stats.sources[0].present);
        assert!(stats.last_ingest.is_none());
    }

    #[test]
    fn filters_structural_and_internal_people_lines() {
        assert!(is_polluting_fact("> Fourni par Dany le 23/09/2026", Some("~/organisation/MEMORY/PEOPLE/eirini.md")));
        assert!(is_polluting_fact("USAGE INTERNE STRICT — ne pas diffuser.", Some("~/organisation/MEMORY/PEOPLE/eirini-dynamiques.md")));
        assert!(is_polluting_fact("## Dynamiques relationnelles", Some("~/organisation/MEMORY/PEOPLE/eirini.md")));
        assert!(is_polluting_fact("Expression émotionnelle :", Some("~/organisation/MEMORY/PEOPLE/eirini-dynamiques.md")));
        assert!(!is_polluting_fact(
            "Validation émotionnelle préalable : Reconnaître ce qu'elle ressent avant d'aborder le fond pratique.",
            Some("~/organisation/MEMORY/PEOPLE/eirini-dynamiques.md")
        ));
    }
}

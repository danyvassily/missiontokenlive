
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
pub struct BrainSource {
    pub path: String,
    pub kind: String,
    pub facts: i64,
    pub present: bool,
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
}

/// Périmètre exclu, affiché tel quel dans l'interface : l'utilisateur doit pouvoir
/// vérifier ce que le cerveau ne lit pas, pas seulement ce qu'il lit.
const NEVER: &[&str] = &[
    "contenu des conversations et des prompts",
    "captures d'écran, frappe clavier, presse-papiers",
    "clés, jetons et mots de passe",
    "données de santé, localisation, identité",
];

pub fn default_path() -> PathBuf {
    dirs_home().join(".gbrain").join("gbrain.sqlite")
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
    let shown = path.to_string_lossy().replace(&dirs_home().to_string_lossy().to_string(), "~");
    let mut out = BrainStats {
        available: false,
        path: shown,
        facts: 0,
        chunks: 0,
        source_count: 0,
        entities: 0,
        last_ingest: None,
        top_entities: vec![],
        recent: vec![],
        sources: vec![],
        never: NEVER.iter().map(|s| s.to_string()).collect(),
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
    out.source_count = count("sources");
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
        "SELECT s.path, s.kind, COUNT(f.id) FROM sources s
         LEFT JOIN facts f ON f.source_id = s.id
         GROUP BY s.path ORDER BY COUNT(f.id) DESC",
    ) {
        if let Ok(rows) = st.query_map([], |r| {
            let raw: String = r.get(0)?;
            Ok(BrainSource {
                path: raw.replace(&dirs_home().to_string_lossy().to_string(), "~"),
                kind: r.get(1)?,
                facts: r.get(2)?,
                present: true,
            })
        }) {
            out.sources = rows.flatten().collect();
        }
    }
    // Sources déclarées dans la configuration mais absentes du disque.
    if let Ok(raw_cfg) = std::fs::read_to_string(dirs_home().join(".gbrain").join("config.json")) {
        if let Ok(cfg) = serde_json::from_str::<serde_json::Value>(&raw_cfg) {
            if let Some(list) = cfg.get("sources").and_then(|v| v.as_array()) {
                for entry in list {
                    let Some(path) = entry.get("path").and_then(|v| v.as_str()) else { continue };
                    let expanded = if let Some(rest) = path.strip_prefix("~/") {
                        dirs_home().join(rest)
                    } else {
                        std::path::PathBuf::from(path)
                    };
                    let shown = path.to_string();
                    if expanded.exists() {
                        if !out.sources.iter().any(|s| s.path == shown) {
                            out.sources.push(BrainSource {
                                path: shown,
                                kind: entry.get("kind").and_then(|v| v.as_str()).unwrap_or("memory").to_string(),
                                facts: 0,
                                present: true,
                            });
                        }
                    } else {
                        out.sources.push(BrainSource {
                            path: shown,
                            kind: entry.get("kind").and_then(|v| v.as_str()).unwrap_or("memory").to_string(),
                            facts: 0,
                            present: false,
                        });
                    }
                }
            }
        }
    }
    out.sources.sort_by(|a, b| b.facts.cmp(&a.facts));

    if let Ok(mut st) = conn.prepare(
        "SELECT f.text, f.kind, f.entity, s.path FROM facts f
         LEFT JOIN sources s ON s.id = f.source_id
         ORDER BY f.id DESC LIMIT 80",
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
            out.recent = rows
                .flatten()
                .filter(|f| !is_polluting_fact(&f.text, f.source.as_deref()))
                .take(8)
                .collect();
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

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

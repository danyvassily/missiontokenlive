
//! Inventaire des clés présentes dans `~/.hermes/.env`.
//!
//! Deux principes non négociables :
//! 1. une clé n'est **jamais** renvoyée en clair par l'inventaire, seulement masquée ;
//! 2. seuls les noms listés ici peuvent être lus (`mtl_key_value`), pour qu'aucun appel
//!    ne puisse extraire une variable arbitraire du fichier d'environnement.

use serde::Serialize;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::PathBuf;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct KeyEntry {
    pub provider: String,
    pub env_var: String,
    pub kind: String,
    pub present: bool,
    pub masked: String,
}

/// (variable d'environnement, nom affiché, famille)
const KNOWN: &[(&str, &str, &str)] = &[
    ("DEEPSEEK_API_KEY", "DeepSeek", "llm"),
    ("ANTHROPIC_API_KEY", "Anthropic", "llm"),
    ("OPENAI_API_KEY", "OpenAI", "llm"),
    ("OPENROUTER_API_KEY", "OpenRouter", "llm"),
    ("ABLITERATION_API_KEY", "Abliteration", "llm"),
    ("MUSEPARK_API_KEY", "Muse Park", "llm"),
    ("GEMINI_API_KEY", "Google Gemini", "llm"),
    ("OPENCODE_ZEN_API_KEY", "OpenCode Zen", "llm"),
    ("ELEVENLABS_API_KEY", "ElevenLabs", "voix"),
    ("MEM0_API_KEY", "Mem0", "mémoire"),
    ("LFM3_API_KEY", "LFM3 (local)", "local"),
];

fn env_path() -> PathBuf {
    dirs_home().join(".hermes").join(".env")
}

fn dirs_home() -> PathBuf {
    std::env::var("HOME").map(PathBuf::from).unwrap_or_else(|_| PathBuf::from("/Users/danyvassily"))
}

/// Masque : garde 3 caractères et les 4 derniers, jamais plus.
pub fn mask(value: &str) -> String {
    let value = value.trim().trim_matches('"').trim_matches('\'');
    if value.is_empty() {
        return String::new();
    }
    if value.len() <= 10 {
        return "•".repeat(value.len().min(6));
    }
    let head: String = value.chars().take(3).collect();
    let tail: String = value.chars().rev().take(4).collect::<Vec<_>>().into_iter().rev().collect();
    format!("{head}…{tail}")
}

fn read_env() -> Vec<(String, String)> {
    let Ok(raw) = std::fs::read_to_string(env_path()) else { return vec![] };
    raw.lines()
        .filter_map(|line| {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                return None;
            }
            let (k, v) = line.split_once('=')?;
            Some((k.trim().to_string(), v.trim().trim_matches('"').to_string()))
        })
        .collect()
}

pub fn inventory() -> Vec<KeyEntry> {
    let env = read_env();
    KNOWN
        .iter()
        .map(|(var, name, kind)| {
            let value = env.iter().find(|(k, _)| k == var).map(|(_, v)| v.clone());
            KeyEntry {
                provider: (*name).to_string(),
                env_var: (*var).to_string(),
                kind: (*kind).to_string(),
                present: value.as_deref().map(|v| !v.is_empty()).unwrap_or(false),
                masked: value.as_deref().map(mask).unwrap_or_default(),
            }
        })
        .collect()
}

/// Valeur en clair, réservée au transfert vers le Trousseau macOS.
/// Retourne un pointeur nul si la variable n'est pas dans la liste blanche.
pub fn value_for(env_var: &str) -> Option<String> {
    if !KNOWN.iter().any(|(v, _, _)| *v == env_var) {
        return None;
    }
    read_env()
        .into_iter()
        .find(|(k, _)| k == env_var)
        .map(|(_, v)| v)
        .filter(|v| !v.is_empty())
}

#[no_mangle]
pub extern "C" fn mtl_keys_json() -> *mut c_char {
    match serde_json::to_string(&inventory()) {
        Ok(s) => CString::new(s).map(|c| c.into_raw()).unwrap_or(std::ptr::null_mut()),
        Err(_) => std::ptr::null_mut(),
    }
}

/// `env_var` doit appartenir à la liste blanche ; sinon pointeur nul.
#[no_mangle]
pub unsafe extern "C" fn mtl_key_value(env_var: *const c_char) -> *mut c_char {
    if env_var.is_null() {
        return std::ptr::null_mut();
    }
    let Ok(name) = CStr::from_ptr(env_var).to_str() else { return std::ptr::null_mut() };
    match value_for(name) {
        Some(v) => CString::new(v).map(|c| c.into_raw()).unwrap_or(std::ptr::null_mut()),
        None => std::ptr::null_mut(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mask_hides_the_secret() {
        let masked = mask("sk-abcdefghijklmnopqrstuvwxyz012345");
        assert!(!masked.contains("abcdefghij"));
        assert!(masked.starts_with("sk-"));
        assert!(masked.ends_with("2345"));
    }

    #[test]
    fn short_values_are_fully_masked() {
        assert_eq!(mask("localdev"), "••••••");
    }

    #[test]
    fn unknown_variable_is_refused() {
        assert!(value_for("PATH").is_none());
        assert!(value_for("HERMES_DASHBOARD_SESSION_TOKEN").is_none());
    }

    #[test]
    fn inventory_never_contains_a_full_key() {
        let env = read_env();
        for entry in inventory() {
            if !entry.present {
                continue;
            }
            if let Some((_, real)) = env.iter().find(|(k, _)| *k == entry.env_var) {
                if real.len() > 12 {
                    assert!(!entry.masked.contains(real.as_str()));
                    assert!(entry.masked.len() < real.len());
                }
            }
        }
    }
}

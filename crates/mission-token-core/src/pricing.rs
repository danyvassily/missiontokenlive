//! Moteur de coût.
//!
//! Principe : un coût n'est calculé que si l'on dispose d'un barème **documenté et
//! versionné**. Sans barème, on renvoie `Unavailable` — jamais 0, jamais une moyenne
//! présentée comme un montant réel.
//!
//! Le barème embarqué ici est explicitement un barème de DÉMONSTRATION, utilisé pour les
//! fixtures et les captures. Il ne doit pas être présenté comme le tarif officiel d'un
//! provider : `pricing_version` le rend visible dans l'interface.

use crate::domain::TokenCounts;
use crate::money::{CostValue, Usd};
use crate::reliability::Reliability;
use serde::{Deserialize, Serialize};

/// Tarif en dollars US par million de tokens.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Rate {
    pub input_per_mtok: f64,
    pub output_per_mtok: f64,
    pub cache_read_per_mtok: f64,
    pub cache_write_per_mtok: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RateEntry {
    pub provider: String,
    /// Préfixe de modèle ; le plus long préfixe correspondant gagne.
    pub model_prefix: String,
    pub rate: Rate,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PricingTable {
    pub version: String,
    pub source: String,
    /// Vrai pour un barème de démonstration : l'interface doit l'indiquer.
    pub is_demo: bool,
    pub entries: Vec<RateEntry>,
}

impl PricingTable {
    /// Barème vide : tout coût est `Unavailable`. C'est le mode par défaut en production
    /// tant qu'aucun barème officiel n'a été validé par l'utilisateur.
    pub fn empty() -> Self {
        Self {
            version: "aucun".into(),
            source: "aucun barème validé".into(),
            is_demo: false,
            entries: vec![],
        }
    }

    /// Barème de démonstration (fixtures, captures, tests).
    pub fn demo() -> Self {
        let mk = |provider: &str, model: &str, i: f64, o: f64, cr: f64| RateEntry {
            provider: provider.into(),
            model_prefix: model.into(),
            rate: Rate { input_per_mtok: i, output_per_mtok: o, cache_read_per_mtok: cr, cache_write_per_mtok: i * 1.25 },
        };
        Self {
            version: "demo-2026.11".into(),
            source: "barème de démonstration — ne pas présenter comme tarif officiel".into(),
            is_demo: true,
            entries: vec![
                mk("openrouter", "deepseek/deepseek-v4.1", 0.14, 0.28, 0.014),
                mk("deepseek", "deepseek-v4", 0.14, 0.28, 0.014),
                mk("deepseek", "deepseek-flash", 0.07, 0.14, 0.007),
                mk("openrouter", "anthropic/claude-sonnet", 3.0, 15.0, 0.30),
                mk("opencode-zen", "sonnet", 3.0, 15.0, 0.30),
            ],
        }
    }

    fn lookup(&self, provider: &str, model: &str) -> Option<&RateEntry> {
        self.entries
            .iter()
            .filter(|e| {
                e.provider.eq_ignore_ascii_case(provider)
                    && model.to_ascii_lowercase().starts_with(&e.model_prefix.to_ascii_lowercase())
            })
            .max_by_key(|e| e.model_prefix.len())
    }

    /// Coût d'un usage. `Real` si l'API a fourni un montant, `Calculated` si le barème
    /// permet de le déduire, `Unavailable` sinon.
    pub fn cost_for(&self, provider: &str, model: &str, tokens: &TokenCounts) -> CostValue {
        if provider.eq_ignore_ascii_case("local") || provider.eq_ignore_ascii_case("ollama") {
            return CostValue::calculated(Usd::ZERO, "exécution locale — aucun coût API", "local");
        }
        match self.lookup(provider, model) {
            Some(entry) => {
                let r = &entry.rate;
                let m = 1_000_000.0;
                let amount = (tokens.input as f64 / m) * r.input_per_mtok
                    + (tokens.output as f64 / m) * r.output_per_mtok
                    + (tokens.cache_read as f64 / m) * r.cache_read_per_mtok
                    + (tokens.cache_write as f64 / m) * r.cache_write_per_mtok
                    + (tokens.reasoning as f64 / m) * r.output_per_mtok;
                CostValue::calculated(
                    Usd::new(amount),
                    format!("tokens mesurés × {}", self.source),
                    self.version.clone(),
                )
            }
            None => CostValue::unavailable(format!(
                "aucun barème documenté pour {provider}/{model}"
            )),
        }
    }

    /// Un montant fourni par une API de facturation est `Real` par définition.
    pub fn real_from_api(amount: f64, source: impl Into<String>) -> CostValue {
        CostValue::real(Usd::new(amount), source)
    }
}

/// Vérifie qu'on ne fabrique jamais un montant : un coût non disponible reste `None`.
pub fn assert_never_invented(cost: &CostValue) -> Result<(), &'static str> {
    if cost.reliability == Reliability::Unavailable && cost.amount.is_some() {
        return Err("un coût Non disponible ne doit jamais porter de montant");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tokens(i: u64, o: u64) -> TokenCounts {
        TokenCounts { input: i, output: o, ..Default::default() }
    }

    #[test]
    fn empty_table_never_invents_a_cost() {
        let t = PricingTable::empty();
        let c = t.cost_for("openrouter", "deepseek/deepseek-v4.1-flash", &tokens(1_000_000, 0));
        assert_eq!(c.reliability, Reliability::Unavailable);
        assert!(c.amount.is_none());
        assert_eq!(c.display(), "—");
        assert!(assert_never_invented(&c).is_ok());
    }

    #[test]
    fn demo_table_calculates_from_measured_tokens() {
        let t = PricingTable::demo();
        let c = t.cost_for("openrouter", "deepseek/deepseek-v4.1-flash", &tokens(1_000_000, 1_000_000));
        assert_eq!(c.reliability, Reliability::Calculated);
        // 0.14 + 0.28 = 0.42
        assert!((c.amount.unwrap().0 - 0.42).abs() < 1e-9);
        assert_eq!(c.pricing_version.as_deref(), Some("demo-2026.11"));
    }

    #[test]
    fn local_models_cost_zero_and_are_calculated() {
        let t = PricingTable::demo();
        let c = t.cost_for("local", "qwen3-coder", &tokens(10, 10));
        assert_eq!(c.reliability, Reliability::Calculated);
        assert_eq!(c.amount.unwrap().0, 0.0);
    }

    #[test]
    fn longest_prefix_wins() {
        let t = PricingTable::demo();
        let a = t.cost_for("deepseek", "deepseek-flash", &tokens(1_000_000, 0));
        let b = t.cost_for("deepseek", "deepseek-v4-pro", &tokens(1_000_000, 0));
        assert!((a.amount.unwrap().0 - 0.07).abs() < 1e-9);
        assert!((b.amount.unwrap().0 - 0.14).abs() < 1e-9);
    }

    #[test]
    fn real_amounts_pass_through() {
        let c = PricingTable::real_from_api(12.481, "API OpenRouter /credits");
        assert_eq!(c.reliability, Reliability::Real);
        assert_eq!(c.display(), "12,48 $");
    }
}

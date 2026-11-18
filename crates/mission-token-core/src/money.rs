//! Montants et états d'une valeur monétaire.

use crate::reliability::Reliability;
use serde::{Deserialize, Serialize};

/// Montant en dollars US, arrondi au centième à l'affichage.
#[derive(Debug, Clone, Copy, PartialEq, PartialOrd, Default, Serialize, Deserialize)]
pub struct Usd(pub f64);

impl Usd {
    pub const ZERO: Usd = Usd(0.0);

    pub fn new(v: f64) -> Self {
        Usd((v * 1_000_000.0).round() / 1_000_000.0)
    }

    pub fn format_fr(&self) -> String {
        // Format français : virgule décimale, deux décimales.
        format!("{:.2} $", self.0).replace('.', ",")
    }

    pub fn add(&self, other: Usd) -> Usd {
        Usd::new(self.0 + other.0)
    }
}

/// Une valeur monétaire accompagnée de sa provenance.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CostValue {
    pub amount: Option<Usd>,
    pub reliability: Reliability,
    /// Origine lisible : « API OpenRouter », « barème v2026.11 », « aucune API »…
    pub source: String,
    /// Version de la grille tarifaire utilisée, si applicable.
    pub pricing_version: Option<String>,
}

impl CostValue {
    pub fn real(amount: Usd, source: impl Into<String>) -> Self {
        Self { amount: Some(amount), reliability: Reliability::Real, source: source.into(), pricing_version: None }
    }

    pub fn calculated(amount: Usd, source: impl Into<String>, pricing_version: impl Into<String>) -> Self {
        Self {
            amount: Some(amount),
            reliability: Reliability::Calculated,
            source: source.into(),
            pricing_version: Some(pricing_version.into()),
        }
    }

    pub fn estimated(amount: Usd, source: impl Into<String>) -> Self {
        Self { amount: Some(amount), reliability: Reliability::Estimated, source: source.into(), pricing_version: None }
    }

    pub fn unavailable(source: impl Into<String>) -> Self {
        Self { amount: None, reliability: Reliability::Unavailable, source: source.into(), pricing_version: None }
    }

    /// Texte affiché : le montant, ou rien si indisponible (jamais « 0,00 $ » par défaut).
    pub fn display(&self) -> String {
        match (self.amount, self.reliability) {
            (Some(a), r) if r.is_displayable_amount() => a.format_fr(),
            _ => "—".to_string(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn french_formatting_uses_comma() {
        assert_eq!(Usd::new(12.482).format_fr(), "12,48 $");
        assert_eq!(Usd::ZERO.format_fr(), "0,00 $");
    }

    #[test]
    fn unavailable_displays_dash_not_zero() {
        let v = CostValue::unavailable("aucune API ne publie cette donnée");
        assert_eq!(v.display(), "—");
        assert_eq!(v.reliability, Reliability::Unavailable);
    }

    #[test]
    fn calculated_carries_pricing_version() {
        let v = CostValue::calculated(Usd::new(0.84), "barème officiel", "2026.11");
        assert_eq!(v.pricing_version.as_deref(), Some("2026.11"));
        assert_eq!(v.display(), "0,84 $");
    }

    #[test]
    fn rounding_is_stable() {
        assert_eq!(Usd::new(0.1 + 0.2).0, 0.3);
    }
}

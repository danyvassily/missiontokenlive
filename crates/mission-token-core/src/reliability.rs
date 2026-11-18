//! Fiabilité d'une donnée affichée.
//!
//! Règle produit absolue : on n'affiche jamais un chiffre sans dire d'où il vient.
//! - `Real`         : montant retourné tel quel par une API officielle (facturation, solde).
//! - `Calculated`   : tokens mesurés × grille tarifaire documentée (versionnée).
//! - `Estimated`    : approximation explicite (moyenne observée, tarif incomplet).
//! - `Unavailable`  : aucune source fiable — on affiche l'absence, jamais un zéro trompeur.

use serde::{Deserialize, Serialize};
use std::fmt;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Reliability {
    Real,
    Calculated,
    Estimated,
    Unavailable,
}

impl Reliability {
    /// Libellé français affiché dans l'interface (badge).
    pub fn label_fr(&self) -> &'static str {
        match self {
            Reliability::Real => "Réel",
            Reliability::Calculated => "Calculé",
            Reliability::Estimated => "Estimé",
            Reliability::Unavailable => "Non disponible",
        }
    }

    /// Rang de fiabilité : plus le chiffre est élevé, moins la donnée est fiable.
    pub fn rank(&self) -> u8 {
        match self {
            Reliability::Real => 0,
            Reliability::Calculated => 1,
            Reliability::Estimated => 2,
            Reliability::Unavailable => 3,
        }
    }

    /// Agrégation : le pire niveau l'emporte (un total mêlant du réel et de l'inconnu
    /// n'est jamais présenté comme réel).
    pub fn worst(self, other: Reliability) -> Reliability {
        if other.rank() > self.rank() { other } else { self }
    }

    /// Une valeur monétaire n'est affichable que si elle a une source.
    pub fn is_displayable_amount(&self) -> bool {
        !matches!(self, Reliability::Unavailable)
    }
}

impl Default for Reliability {
    fn default() -> Self {
        Reliability::Unavailable
    }
}

impl fmt::Display for Reliability {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.label_fr())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn labels_are_french_and_stable() {
        assert_eq!(Reliability::Real.label_fr(), "Réel");
        assert_eq!(Reliability::Calculated.label_fr(), "Calculé");
        assert_eq!(Reliability::Estimated.label_fr(), "Estimé");
        assert_eq!(Reliability::Unavailable.label_fr(), "Non disponible");
    }

    #[test]
    fn worst_reliability_wins() {
        assert_eq!(Reliability::Real.worst(Reliability::Calculated), Reliability::Calculated);
        assert_eq!(Reliability::Estimated.worst(Reliability::Unavailable), Reliability::Unavailable);
        assert_eq!(Reliability::Real.worst(Reliability::Real), Reliability::Real);
    }

    #[test]
    fn unavailable_is_never_a_displayable_amount() {
        assert!(!Reliability::Unavailable.is_displayable_amount());
        assert!(Reliability::Real.is_displayable_amount());
        assert!(Reliability::Calculated.is_displayable_amount());
    }
}

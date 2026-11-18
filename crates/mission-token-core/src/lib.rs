//! mission-token-core — domaine, fiabilité des données et moteur de coût.
//!
//! Ce crate ne fait aucune E/S : il est testable seul et partagé par le stockage,
//! les collecteurs et la FFI.

pub mod domain;
pub mod money;
pub mod pricing;
pub mod reliability;

pub use domain::*;
pub use money::{CostValue, Usd};
pub use pricing::{PricingTable, Rate, RateEntry};
pub use reliability::Reliability;

/// Version du protocole JSON échangé avec l'interface SwiftUI.
pub const PROTOCOL_VERSION: &str = "1";

pub fn crate_version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

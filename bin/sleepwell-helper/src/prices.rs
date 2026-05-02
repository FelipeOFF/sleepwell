//! Embedded price table loaded from `prices.toml` at compile time.

use serde::Deserialize;
use std::collections::BTreeMap;

const PRICES_TOML: &str = include_str!("../prices.toml");

#[derive(Debug, Clone, Deserialize)]
pub struct ModelPrice {
    pub input: f64,
    pub output: f64,
    #[serde(default)]
    pub cache_read: Option<f64>,
    #[serde(default)]
    pub cache_creation: Option<f64>,
}

pub type VendorTable = BTreeMap<String, ModelPrice>;
pub type PriceTable = BTreeMap<String, VendorTable>;

pub fn load() -> PriceTable {
    toml::from_str::<PriceTable>(PRICES_TOML).expect("embedded prices.toml must parse")
}

pub fn lookup<'a>(table: &'a PriceTable, vendor: &str, model: &str) -> Option<&'a ModelPrice> {
    table.get(vendor).and_then(|v| v.get(model))
}

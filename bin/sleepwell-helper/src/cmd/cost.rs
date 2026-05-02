//! `cost` subcommand: USD cost computation from parsed usage + embedded prices.

use anyhow::{Context, Result};
use clap::Args;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::fs;
use std::io::{self, Read};
use std::path::PathBuf;

use sleepwell_helper::prices::{self, ModelPrice};

#[derive(Debug, Args)]
pub struct CostArgs {
    /// Vendor key (claude, openai, google).
    #[arg(long)]
    pub format: String,
    /// Model key (e.g. sonnet-4-5).
    #[arg(long)]
    pub model: String,
    /// Read parsed usage from a file instead of stdin.
    #[arg(long)]
    pub input: Option<PathBuf>,
}

#[derive(Debug, Deserialize)]
struct ParsedTotals {
    #[serde(default)]
    input: u64,
    #[serde(default)]
    output: u64,
    #[serde(default)]
    cache_read: u64,
    #[serde(default)]
    cache_creation: u64,
}

#[derive(Debug, Deserialize)]
struct ParsedDoc {
    #[serde(default)]
    totals: Option<ParsedTotals>,
}

#[derive(Debug, Serialize)]
struct Breakdown {
    input: f64,
    output: f64,
    cache_read: f64,
    cache_creation: f64,
}

pub fn run(args: CostArgs) -> Result<()> {
    let raw = read_input(&args.input)?;
    let totals = extract_totals(&raw)?;

    let table = prices::load();
    let price = match prices::lookup(&table, &args.format, &args.model) {
        Some(p) => p,
        None => {
            eprintln!(
                "warning: unknown model {}/{} — emitting null cost",
                args.format, args.model
            );
            let out = json!({
                "cost_usd": Value::Null,
                "error": "unknown model",
                "model": args.model,
                "vendor": args.format,
            });
            println!("{}", serde_json::to_string(&out)?);
            return Ok(());
        }
    };

    let breakdown = compute(&totals, price);
    let cost_usd = breakdown.input + breakdown.output + breakdown.cache_read + breakdown.cache_creation;

    let out = json!({
        "cost_usd": cost_usd,
        "breakdown": breakdown,
        "model": args.model,
        "vendor": args.format,
    });
    println!("{}", serde_json::to_string(&out)?);
    Ok(())
}

fn read_input(path: &Option<PathBuf>) -> Result<String> {
    match path {
        Some(p) => fs::read_to_string(p).with_context(|| format!("read {:?}", p)),
        None => {
            let mut buf = String::new();
            io::stdin()
                .read_to_string(&mut buf)
                .context("read stdin")?;
            Ok(buf)
        }
    }
}

fn extract_totals(raw: &str) -> Result<ParsedTotals> {
    let doc: ParsedDoc = serde_json::from_str(raw.trim()).context("parse usage JSON")?;
    Ok(doc.totals.unwrap_or(ParsedTotals {
        input: 0,
        output: 0,
        cache_read: 0,
        cache_creation: 0,
    }))
}

fn compute(t: &ParsedTotals, p: &ModelPrice) -> Breakdown {
    let m = 1_000_000.0;
    Breakdown {
        input: (t.input as f64) * p.input / m,
        output: (t.output as f64) * p.output / m,
        cache_read: (t.cache_read as f64) * p.cache_read.unwrap_or(0.0) / m,
        cache_creation: (t.cache_creation as f64) * p.cache_creation.unwrap_or(0.0) / m,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn computes_claude_sonnet_cost() {
        let totals = ParsedTotals {
            input: 1_000_000,
            output: 1_000_000,
            cache_read: 1_000_000,
            cache_creation: 1_000_000,
        };
        let table = prices::load();
        let p = prices::lookup(&table, "claude", "sonnet-4-5").unwrap();
        let b = compute(&totals, p);
        assert!((b.input - 3.0).abs() < 1e-9);
        assert!((b.output - 15.0).abs() < 1e-9);
        assert!((b.cache_read - 0.30).abs() < 1e-9);
        assert!((b.cache_creation - 3.75).abs() < 1e-9);
    }

    #[test]
    fn extract_handles_full_doc() {
        let raw = r#"{"format":"claude","turns":2,"totals":{"input":100,"output":50,"cache_read":10,"cache_creation":5}}"#;
        let t = extract_totals(raw).unwrap();
        assert_eq!(t.input, 100);
        assert_eq!(t.output, 50);
        assert_eq!(t.cache_read, 10);
        assert_eq!(t.cache_creation, 5);
    }
}

//! `calibrate` subcommand: compute merge-rate per intent category.
//!
//! Walks the sleepwell archive (default `.sleepwell/archive/`), reads each
//! `state.json`, classifies the intent into one of {refactor, feat, fix,
//! test, docs, chore} and checks whether the corresponding archived branch
//! was merged into the base branch (via `git branch --merged <base>`).
//!
//! Emits a JSON object on stdout:
//! ```json
//! {"overall":0.62,"by_category":{"refactor":0.78},"trusted":["refactor"],
//!  "distrusted":["radical"],"n_runs":12}
//! ```

use anyhow::{Context, Result};
use clap::Args;
use regex::Regex;
use serde::Serialize;
use serde_json::Value;
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Debug, Args)]
pub struct CalibrateArgs {
    /// Archive directory containing per-run state.json files.
    #[arg(long, default_value = ".sleepwell/archive/")]
    pub archive: PathBuf,
    /// Repository root.
    #[arg(long, default_value = ".")]
    pub repo: PathBuf,
    /// Base branch (auto-detected via origin/HEAD when omitted).
    #[arg(long)]
    pub base_branch: Option<String>,
}

#[derive(Debug, Serialize)]
struct Output {
    overall: f64,
    by_category: BTreeMap<String, f64>,
    trusted: Vec<String>,
    distrusted: Vec<String>,
    n_runs: usize,
}

pub fn run(args: CalibrateArgs) -> Result<()> {
    let base = match args.base_branch {
        Some(b) => b,
        None => detect_base(&args.repo).unwrap_or_else(|| "main".to_string()),
    };

    let runs = match collect_runs(&args.archive) {
        Ok(v) => v,
        Err(e) => {
            eprintln!("calibrate: archive vazio ou ilegível ({}); usando defaults", e);
            print_defaults()?;
            return Ok(());
        }
    };
    if runs.is_empty() {
        eprintln!("calibrate: nenhum run em {:?}; usando defaults", args.archive);
        print_defaults()?;
        return Ok(());
    }

    let merged = merged_branches(&args.repo, &base).unwrap_or_default();

    let mut totals: BTreeMap<String, (u32, u32)> = BTreeMap::new(); // (merged, total)
    for run in &runs {
        let cat = run.category.clone().unwrap_or_else(|| "other".to_string());
        let entry = totals.entry(cat).or_insert((0, 0));
        entry.1 += 1;
        let absorbed = run
            .branch
            .as_deref()
            .map(|b| {
                merged.iter().any(|m| m == b) || cherry_picked(&args.repo, b, &base)
            })
            .unwrap_or(false);
        if absorbed {
            entry.0 += 1;
        }
    }

    let total_runs: u32 = totals.values().map(|(_, t)| t).sum();
    let total_merged: u32 = totals.values().map(|(m, _)| m).sum();
    let overall = if total_runs == 0 {
        0.0
    } else {
        total_merged as f64 / total_runs as f64
    };

    let mut by_category = BTreeMap::new();
    let mut trusted = Vec::new();
    let mut distrusted = Vec::new();
    for (cat, (m, t)) in &totals {
        let rate = if *t == 0 { 0.0 } else { *m as f64 / *t as f64 };
        by_category.insert(cat.clone(), round2(rate));
        if *t >= 3 && rate >= 0.7 {
            trusted.push(cat.clone());
        }
        if *t >= 3 && rate <= 0.3 {
            distrusted.push(cat.clone());
        }
    }

    let out = Output {
        overall: round2(overall),
        by_category,
        trusted,
        distrusted,
        n_runs: runs.len(),
    };
    println!("{}", serde_json::to_string(&out)?);
    Ok(())
}

fn print_defaults() -> Result<()> {
    let out = Output {
        overall: 0.0,
        by_category: BTreeMap::new(),
        trusted: vec![],
        distrusted: vec![],
        n_runs: 0,
    };
    println!("{}", serde_json::to_string(&out)?);
    Ok(())
}

fn round2(x: f64) -> f64 {
    (x * 100.0).round() / 100.0
}

#[derive(Debug)]
struct Run {
    category: Option<String>,
    branch: Option<String>,
}

fn collect_runs(archive: &Path) -> Result<Vec<Run>> {
    let mut runs = Vec::new();
    let entries = fs::read_dir(archive).with_context(|| format!("read_dir {:?}", archive))?;
    for entry in entries.flatten() {
        let p = entry.path();
        let state_path = if p.is_dir() {
            p.join("state.json")
        } else if p.file_name().map(|n| n == "state.json").unwrap_or(false) {
            p
        } else {
            continue;
        };
        if !state_path.exists() {
            continue;
        }
        let raw = match fs::read_to_string(&state_path) {
            Ok(r) => r,
            Err(_) => continue,
        };
        let v: Value = match serde_json::from_str(&raw) {
            Ok(v) => v,
            Err(_) => continue,
        };
        let intent = v.get("intent").and_then(|x| x.as_str()).unwrap_or("");
        let branch = v
            .get("branch")
            .and_then(|x| x.as_str())
            .map(|s| s.to_string());
        runs.push(Run {
            category: classify_intent(intent),
            branch,
        });
    }
    Ok(runs)
}

fn classify_intent(intent: &str) -> Option<String> {
    let re = Regex::new(r"(?i)\b(refactor|feat|fix|test|docs|chore)\b").ok()?;
    re.captures(intent)
        .and_then(|c| c.get(1))
        .map(|m| m.as_str().to_ascii_lowercase())
}

fn detect_base(repo: &Path) -> Option<String> {
    let out = Command::new("git")
        .args(["symbolic-ref", "refs/remotes/origin/HEAD"])
        .current_dir(repo)
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
    s.rsplit('/').next().map(|x| x.to_string())
}

fn merged_branches(repo: &Path, base: &str) -> Result<Vec<String>> {
    let out = Command::new("git")
        .args(["branch", "--merged", base, "--format=%(refname:short)"])
        .current_dir(repo)
        .output()
        .context("git branch --merged")?;
    if !out.status.success() {
        anyhow::bail!("git branch --merged failed");
    }
    Ok(String::from_utf8_lossy(&out.stdout)
        .lines()
        .map(|l| l.trim().to_string())
        .filter(|l| !l.is_empty())
        .collect())
}

fn cherry_picked(repo: &Path, branch: &str, base: &str) -> bool {
    // `git cherry <upstream> <head>` lists commits in <head> not yet upstream.
    // Empty output ⇒ all absorbed.
    let out = match Command::new("git")
        .args(["cherry", base, branch])
        .current_dir(repo)
        .output()
    {
        Ok(o) => o,
        Err(_) => return false,
    };
    if !out.status.success() {
        return false;
    }
    let s = String::from_utf8_lossy(&out.stdout);
    !s.lines().any(|l| l.trim_start().starts_with('+'))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn classifies_known_intents() {
        assert_eq!(classify_intent("refactor: extract X").as_deref(), Some("refactor"));
        assert_eq!(classify_intent("feat new endpoint").as_deref(), Some("feat"));
        assert_eq!(classify_intent("FIX bug"), Some("fix".to_string()));
        assert_eq!(classify_intent("plain idea"), None);
    }

    #[test]
    fn round_two_decimals() {
        assert_eq!(round2(0.66666), 0.67);
        assert_eq!(round2(0.5), 0.5);
    }
}

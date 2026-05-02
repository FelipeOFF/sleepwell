//! `evaluate` subcommand: heuristic rating of an iteration.
//!
//! Reads three optional inputs:
//!   * `--state <path>`      — sleepwell state.json
//!   * `--diff-stat <path>`  — output of `git diff --stat`
//!   * `--last-notes <path>` — notes.md (or `-` for stdin)
//!
//! Produces a JSON object on stdout:
//! ```json
//! {"rating":N,"observation":"...","course_correct":bool}
//! ```
//!
//! Heuristic (no LLM):
//! base 3, +2 PASS / -2 FAIL on previous iter, +1 normal churn / -1 huge
//! churn, +1 conventional commit / -1 unresolved TODO/FIXME.

use anyhow::{Context, Result};
use clap::Args;
use regex::Regex;
use serde::Serialize;
use serde_json::Value;
use std::fs;
use std::io::{self, Read};
use std::path::PathBuf;

#[derive(Debug, Args)]
pub struct EvaluateArgs {
    /// Path to state.json (sleepwell run state).
    #[arg(long)]
    pub state: Option<PathBuf>,
    /// Path to file containing `git diff --stat` output.
    #[arg(long)]
    pub diff_stat: Option<PathBuf>,
    /// Path to notes.md, or `-` to read from stdin.
    #[arg(long)]
    pub last_notes: Option<String>,
}

#[derive(Debug, Serialize)]
struct Output {
    rating: i32,
    observation: String,
    course_correct: bool,
}

pub fn run(args: EvaluateArgs) -> Result<()> {
    let state = args
        .state
        .as_deref()
        .map(|p| {
            fs::read_to_string(p)
                .with_context(|| format!("read state {:?}", p))
                .and_then(|s| serde_json::from_str::<Value>(&s).context("parse state json"))
        })
        .transpose()?;
    let diff_stat = args
        .diff_stat
        .as_deref()
        .map(|p| fs::read_to_string(p).with_context(|| format!("read diff-stat {:?}", p)))
        .transpose()?
        .unwrap_or_default();
    let notes = match args.last_notes.as_deref() {
        Some("-") => {
            let mut buf = String::new();
            io::stdin().read_to_string(&mut buf)?;
            buf
        }
        Some(p) => fs::read_to_string(p).with_context(|| format!("read notes {}", p))?,
        None => String::new(),
    };

    let out = score(state.as_ref(), &diff_stat, &notes);
    println!("{}", serde_json::to_string(&out)?);
    Ok(())
}

fn score(state: Option<&Value>, diff_stat: &str, notes: &str) -> Output {
    let mut rating: i32 = 3;
    let mut reasons: Vec<&'static str> = Vec::new();

    // Previous iteration outcome.
    let last_outcome = state
        .and_then(|s| s.get("last_outcome").or_else(|| s.get("outcome")))
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_ascii_uppercase();
    if last_outcome == "PASS" {
        rating += 2;
        reasons.push("último iter PASS");
    } else if last_outcome == "FAIL" {
        rating -= 2;
        reasons.push("último iter FAIL");
    }

    // Diff stat churn analysis.
    if let Some((files, ins, dels)) = parse_diff_stat(diff_stat) {
        let churn = if dels == 0 {
            ins as f64
        } else {
            ins as f64 / dels as f64
        };
        if files >= 1 && (0.5..=3.0).contains(&churn) {
            rating += 1;
            reasons.push("churn saudável");
        }
        if churn > 5.0 {
            rating -= 1;
            reasons.push("churn excessivo");
        }
    }

    // Conventional commit on the most recent message.
    let conv =
        Regex::new(r"^(feat|fix|refactor|docs|test|chore|perf)(\(.+\))?:").expect("regex compile");
    let last_msg = state
        .and_then(|s| {
            s.get("last_commit_msg")
                .or_else(|| s.get("last_commit"))
                .or_else(|| s.get("commit_msg"))
        })
        .and_then(|v| v.as_str())
        .unwrap_or("");
    if conv.is_match(last_msg) {
        rating += 1;
        reasons.push("commit conventional");
    }

    // TODO / FIXME left in notes.
    let upper = notes.to_ascii_uppercase();
    if upper.contains("TODO") || upper.contains("FIXME") {
        rating -= 1;
        reasons.push("TODO/FIXME pendentes");
    }

    let rating = rating.clamp(1, 5);
    let observation = if reasons.is_empty() {
        "sem sinais relevantes".to_string()
    } else {
        reasons.join("; ")
    };
    Output {
        rating,
        observation,
        course_correct: rating <= 2,
    }
}

/// Parse the last summary line of `git diff --stat`, e.g.
/// ` 3 files changed, 42 insertions(+), 5 deletions(-)`.
fn parse_diff_stat(s: &str) -> Option<(u32, u32, u32)> {
    let summary = s
        .lines()
        .rev()
        .find(|l| l.contains("changed"))
        .unwrap_or("");
    let files = capture_num(summary, r"(\d+)\s+files?\s+changed").unwrap_or(0);
    let ins = capture_num(summary, r"(\d+)\s+insertions?").unwrap_or(0);
    let dels = capture_num(summary, r"(\d+)\s+deletions?").unwrap_or(0);
    if files == 0 && ins == 0 && dels == 0 {
        None
    } else {
        Some((files, ins, dels))
    }
}

fn capture_num(s: &str, pat: &str) -> Option<u32> {
    let re = Regex::new(pat).ok()?;
    re.captures(s)?.get(1)?.as_str().parse().ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn pass_clean_iteration_high_rating() {
        let state = json!({"last_outcome":"PASS","last_commit_msg":"feat: add x"});
        let diff = " 2 files changed, 30 insertions(+), 15 deletions(-)\n";
        let out = score(Some(&state), diff, "tudo ok");
        // 3 + 2 (PASS) + 1 (churn) + 1 (conv) = 7 -> clamp 5
        assert_eq!(out.rating, 5);
        assert!(!out.course_correct);
    }

    #[test]
    fn fail_with_huge_churn() {
        let state = json!({"last_outcome":"FAIL","last_commit_msg":"wip"});
        let diff = " 4 files changed, 600 insertions(+), 50 deletions(-)\n";
        let out = score(Some(&state), diff, "TODO: revisitar");
        // 3 - 2 (FAIL) - 1 (churn>5) - 1 (TODO) = -1 -> clamp 1
        assert_eq!(out.rating, 1);
        assert!(out.course_correct);
    }

    #[test]
    fn pass_with_huge_churn_yields_neutral() {
        let state = json!({"last_outcome":"PASS","last_commit_msg":"refactor(x): y"});
        // churn = 1000/10 = 100 -> -1
        let diff = " 5 files changed, 1000 insertions(+), 10 deletions(-)\n";
        let out = score(Some(&state), diff, "");
        // 3 + 2 - 1 + 1 = 5
        assert_eq!(out.rating, 5);
    }

    #[test]
    fn empty_inputs_neutral() {
        let out = score(None, "", "");
        assert_eq!(out.rating, 3);
        assert!(!out.course_correct);
    }
}

use anyhow::Result;
use clap::{Parser, Subcommand};

mod cmd;

use cmd::{
    calibrate::CalibrateArgs, cost::CostArgs, evaluate::EvaluateArgs, hash::HashArgs,
    parse_jsonl::ParseJsonlArgs, watch::WatchArgs,
};

#[derive(Debug, Parser)]
#[command(
    name = "sleepwell-helper",
    version,
    about = "Helper utilities for the Sleepwell Claude Code plugin"
)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Debug, Subcommand)]
enum Command {
    /// Parse a JSONL transcript (Claude/Codex/Gemini/Generic) and emit token totals.
    ParseJsonl(ParseJsonlArgs),
    /// Compute USD cost from parsed usage using the embedded price table.
    Cost(CostArgs),
    /// Hash a file's content (used by content-hash caches).
    Hash(HashArgs),
    /// Watch a path for changes.
    Watch(WatchArgs),
    /// Evaluate plugin output against expectations.
    Evaluate(EvaluateArgs),
    /// Calibrate plugin parameters from historical runs.
    Calibrate(CalibrateArgs),
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Command::ParseJsonl(a) => cmd::parse_jsonl::run(a),
        Command::Cost(a) => cmd::cost::run(a),
        Command::Hash(a) => cmd::hash::run(a),
        Command::Watch(a) => cmd::watch::run(a),
        Command::Evaluate(a) => cmd::evaluate::run(a),
        Command::Calibrate(a) => cmd::calibrate::run(a),
    }
}

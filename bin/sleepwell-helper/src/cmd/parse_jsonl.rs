//! `parse-jsonl` subcommand stub. Multi-LLM implementation lands in #17.

use anyhow::Result;
use clap::Args;
use std::path::PathBuf;

#[derive(Debug, Args)]
pub struct ParseJsonlArgs {
    /// Path to the JSONL transcript.
    pub file: PathBuf,
    /// Format hint: auto|claude|codex|gemini|generic.
    #[arg(long, default_value = "auto")]
    pub format: String,
}

pub fn run(_args: ParseJsonlArgs) -> Result<()> {
    anyhow::bail!("parse-jsonl not yet implemented (see issue #17)")
}

//! `cost` subcommand stub. Pricing logic lands in #18.

use anyhow::Result;
use clap::Args;
use std::path::PathBuf;

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

pub fn run(_args: CostArgs) -> Result<()> {
    anyhow::bail!("cost not yet implemented (see issue #18)")
}

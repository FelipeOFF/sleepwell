//! `evaluate` subcommand stub.

use anyhow::Result;
use clap::Args;

#[derive(Debug, Args)]
pub struct EvaluateArgs {}

pub fn run(_args: EvaluateArgs) -> Result<()> {
    anyhow::bail!("evaluate not yet implemented")
}

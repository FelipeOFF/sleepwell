//! `calibrate` subcommand stub.

use anyhow::Result;
use clap::Args;

#[derive(Debug, Args)]
pub struct CalibrateArgs {}

pub fn run(_args: CalibrateArgs) -> Result<()> {
    anyhow::bail!("calibrate not yet implemented")
}

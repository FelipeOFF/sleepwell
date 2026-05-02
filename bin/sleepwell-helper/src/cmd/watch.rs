//! `watch` subcommand stub.

use anyhow::Result;
use clap::Args;
use std::path::PathBuf;

#[derive(Debug, Args)]
pub struct WatchArgs {
    pub path: PathBuf,
}

pub fn run(_args: WatchArgs) -> Result<()> {
    anyhow::bail!("watch not yet implemented")
}

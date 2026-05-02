//! `hash` subcommand: blake3 hashing of stdin lines or positional inputs.
//!
//! Reads from stdin (one input per line) when no positional arguments are given,
//! otherwise hashes each positional argument as a UTF-8 byte sequence. Each
//! input produces a single line of lowercase hex on stdout (32-byte blake3
//! digest, 64 hex chars).

use anyhow::Result;
use clap::Args;
use std::io::{self, BufRead, Write};

#[derive(Debug, Args)]
pub struct HashArgs {
    /// Inputs to hash. When omitted, reads one input per line from stdin.
    pub inputs: Vec<String>,
}

pub fn run(args: HashArgs) -> Result<()> {
    let stdout = io::stdout();
    let mut out = stdout.lock();

    if args.inputs.is_empty() {
        let stdin = io::stdin();
        for line in stdin.lock().lines() {
            let line = line?;
            writeln!(out, "{}", hash_str(&line))?;
        }
    } else {
        for input in &args.inputs {
            writeln!(out, "{}", hash_str(input))?;
        }
    }
    Ok(())
}

fn hash_str(s: &str) -> String {
    blake3::hash(s.as_bytes()).to_hex().to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hashes_known_value() {
        assert_eq!(
            hash_str("foo"),
            "04e0bb39f30b1a3feb89f536c93be15055482df748674b00d26e5a75777702e9"
        );
    }

    #[test]
    fn hex_length_is_64() {
        assert_eq!(hash_str("anything").len(), 64);
    }
}

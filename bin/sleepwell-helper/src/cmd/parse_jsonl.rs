//! `parse-jsonl` subcommand: tolerant multi-LLM JSONL transcript parser.

use anyhow::{Context, Result};
use clap::Args;
use serde::Serialize;
use serde_json::Value;
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::PathBuf;

use sleepwell_helper::format_detect::{detect_from_path, LlmFormat};
use sleepwell_helper::usage::Usage;

#[derive(Debug, Args)]
pub struct ParseJsonlArgs {
    /// Path to the JSONL transcript.
    pub file: PathBuf,
    /// Format hint: auto|claude|codex|gemini|generic.
    #[arg(long, default_value = "auto")]
    pub format: String,
}

#[derive(Debug, Serialize)]
struct Output {
    format: &'static str,
    turns: u64,
    totals: Usage,
}

pub fn run(args: ParseJsonlArgs) -> Result<()> {
    let format = match args.format.to_ascii_lowercase().as_str() {
        "auto" => detect_from_path(&args.file),
        "claude" => LlmFormat::Claude,
        "codex" => LlmFormat::Codex,
        "gemini" => LlmFormat::Gemini,
        "generic" => LlmFormat::Generic,
        other => anyhow::bail!("unknown --format: {}", other),
    };

    let result = parse_file(&args.file, format)?;
    let out = Output {
        format: format.as_str(),
        turns: result.turns,
        totals: result.totals,
    };
    println!("{}", serde_json::to_string(&out)?);
    Ok(())
}

#[derive(Default, Debug)]
pub struct ParseResult {
    pub turns: u64,
    pub totals: Usage,
}

pub fn parse_file(path: &PathBuf, format: LlmFormat) -> Result<ParseResult> {
    let f = File::open(path).with_context(|| format!("open {:?}", path))?;
    let reader = BufReader::new(f);
    let mut result = ParseResult::default();
    for line in reader.lines() {
        let line = match line {
            Ok(l) => l,
            Err(_) => continue,
        };
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let value: Value = match serde_json::from_str(trimmed) {
            Ok(v) => v,
            Err(_) => continue,
        };
        if let Some(usage) = extract_usage(&value, format) {
            result.totals.add(&usage);
            result.turns += 1;
        } else {
            // Lines without usage may still be a turn — count only when we found usage.
        }
    }
    Ok(result)
}

fn extract_usage(value: &Value, format: LlmFormat) -> Option<Usage> {
    match format {
        LlmFormat::Claude => extract_claude(value),
        LlmFormat::Codex => extract_codex(value),
        LlmFormat::Gemini => extract_gemini(value),
        LlmFormat::Generic => extract_generic(value),
    }
}

/// Claude transcripts: usage may live at root or inside `message.usage`.
fn extract_claude(v: &Value) -> Option<Usage> {
    let usage = v
        .get("message")
        .and_then(|m| m.get("usage"))
        .or_else(|| v.get("usage"))?;
    Some(Usage {
        input: u(usage, "input_tokens"),
        output: u(usage, "output_tokens"),
        cache_read: u(usage, "cache_read_input_tokens"),
        cache_creation: u(usage, "cache_creation_input_tokens"),
    })
}

/// Codex / OpenAI: prompt_tokens / completion_tokens.
fn extract_codex(v: &Value) -> Option<Usage> {
    let usage = v
        .get("usage")
        .or_else(|| v.get("response").and_then(|r| r.get("usage")))?;
    Some(Usage {
        input: u(usage, "prompt_tokens"),
        output: u(usage, "completion_tokens"),
        cache_read: u(usage, "cached_tokens"),
        cache_creation: 0,
    })
}

/// Gemini: usageMetadata.promptTokenCount / candidatesTokenCount.
fn extract_gemini(v: &Value) -> Option<Usage> {
    let usage = v
        .get("usageMetadata")
        .or_else(|| v.get("usage_metadata"))
        .or_else(|| v.get("usage"))?;
    let input = u(usage, "promptTokenCount").max(u(usage, "prompt_token_count"));
    let output = u(usage, "candidatesTokenCount").max(u(usage, "candidates_token_count"));
    let cached = u(usage, "cachedContentTokenCount").max(u(usage, "cached_content_token_count"));
    Some(Usage {
        input,
        output,
        cache_read: cached,
        cache_creation: 0,
    })
}

/// Generic: try the union of common keys.
fn extract_generic(v: &Value) -> Option<Usage> {
    let usage = v.get("usage")?;
    Some(Usage {
        input: u(usage, "input_tokens").max(u(usage, "prompt_tokens")),
        output: u(usage, "output_tokens").max(u(usage, "completion_tokens")),
        cache_read: u(usage, "cache_read_input_tokens").max(u(usage, "cached_tokens")),
        cache_creation: u(usage, "cache_creation_input_tokens"),
    })
}

fn u(v: &Value, key: &str) -> u64 {
    v.get(key).and_then(|x| x.as_u64()).unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn claude_root_usage() {
        let v = json!({"usage": {"input_tokens": 10, "output_tokens": 5, "cache_read_input_tokens": 2, "cache_creation_input_tokens": 1}});
        let u = extract_claude(&v).unwrap();
        assert_eq!(
            u,
            Usage {
                input: 10,
                output: 5,
                cache_read: 2,
                cache_creation: 1
            }
        );
    }

    #[test]
    fn claude_nested_message_usage() {
        let v = json!({"message": {"usage": {"input_tokens": 7, "output_tokens": 3}}});
        let u = extract_claude(&v).unwrap();
        assert_eq!(u.input, 7);
        assert_eq!(u.output, 3);
    }

    #[test]
    fn codex_usage() {
        let v =
            json!({"usage": {"prompt_tokens": 100, "completion_tokens": 40, "cached_tokens": 10}});
        let u = extract_codex(&v).unwrap();
        assert_eq!(
            u,
            Usage {
                input: 100,
                output: 40,
                cache_read: 10,
                cache_creation: 0
            }
        );
    }

    #[test]
    fn gemini_usage() {
        let v = json!({"usageMetadata": {"promptTokenCount": 50, "candidatesTokenCount": 20}});
        let u = extract_gemini(&v).unwrap();
        assert_eq!(u.input, 50);
        assert_eq!(u.output, 20);
    }
}

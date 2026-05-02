//! Detect a JSONL transcript's source LLM by looking at its file path.

use serde::{Deserialize, Serialize};
use std::path::Path;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum LlmFormat {
    Claude,
    Codex,
    Gemini,
    Generic,
}

impl LlmFormat {
    pub fn as_str(&self) -> &'static str {
        match self {
            LlmFormat::Claude => "claude",
            LlmFormat::Codex => "codex",
            LlmFormat::Gemini => "gemini",
            LlmFormat::Generic => "generic",
        }
    }

    pub fn parse(s: &str) -> Option<Self> {
        match s.to_ascii_lowercase().as_str() {
            "claude" => Some(LlmFormat::Claude),
            "codex" => Some(LlmFormat::Codex),
            "gemini" => Some(LlmFormat::Gemini),
            "generic" => Some(LlmFormat::Generic),
            "auto" => None,
            _ => None,
        }
    }
}

/// Heuristic detection from path; matches typical CLI cache directories.
pub fn detect_from_path<P: AsRef<Path>>(path: P) -> LlmFormat {
    let s = path.as_ref().to_string_lossy().to_string();
    if s.contains("/.claude/projects/") || s.contains("/.claude/sessions/") {
        LlmFormat::Claude
    } else if s.contains("/.codex/sessions/") || s.contains("/.codex/") {
        LlmFormat::Codex
    } else if s.contains("/.gemini/") {
        LlmFormat::Gemini
    } else {
        LlmFormat::Generic
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_claude() {
        assert_eq!(
            detect_from_path("/Users/x/.claude/projects/foo/bar.jsonl"),
            LlmFormat::Claude
        );
    }

    #[test]
    fn detects_codex() {
        assert_eq!(
            detect_from_path("/Users/x/.codex/sessions/abc.jsonl"),
            LlmFormat::Codex
        );
    }

    #[test]
    fn detects_gemini() {
        assert_eq!(
            detect_from_path("/Users/x/.gemini/foo.jsonl"),
            LlmFormat::Gemini
        );
    }

    #[test]
    fn fallback_generic() {
        assert_eq!(detect_from_path("/tmp/anything.jsonl"), LlmFormat::Generic);
    }
}

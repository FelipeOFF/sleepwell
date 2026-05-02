use assert_cmd::Command;
use serde_json::Value;

fn run_parse(file: &str, format: &str) -> Value {
    let out = Command::cargo_bin("sleepwell-helper")
        .unwrap()
        .args(["parse-jsonl", file, "--format", format])
        .output()
        .unwrap();
    assert!(
        out.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    serde_json::from_slice(&out.stdout).expect("stdout must be JSON")
}

#[test]
fn parses_claude_fixture() {
    let v = run_parse("tests/fixtures/claude_sample.jsonl", "claude");
    assert_eq!(v["format"], "claude");
    assert_eq!(v["turns"], 2);
    assert_eq!(v["totals"]["input"], 200);
    assert_eq!(v["totals"]["output"], 45);
    assert_eq!(v["totals"]["cache_read"], 60);
    assert_eq!(v["totals"]["cache_creation"], 200);
}

#[test]
fn parses_codex_fixture() {
    let v = run_parse("tests/fixtures/codex_sample.jsonl", "codex");
    assert_eq!(v["format"], "codex");
    assert_eq!(v["turns"], 2);
    assert_eq!(v["totals"]["input"], 350);
    assert_eq!(v["totals"]["output"], 135);
    assert_eq!(v["totals"]["cache_read"], 40);
}

#[test]
fn parses_gemini_fixture() {
    let v = run_parse("tests/fixtures/gemini_sample.jsonl", "gemini");
    assert_eq!(v["format"], "gemini");
    assert_eq!(v["turns"], 2);
    assert_eq!(v["totals"]["input"], 400);
    assert_eq!(v["totals"]["output"], 160);
    assert_eq!(v["totals"]["cache_read"], 50);
}

#[test]
fn auto_detects_generic_when_path_unknown() {
    let v = run_parse("tests/fixtures/claude_sample.jsonl", "auto");
    // Path doesn't include ~/.claude/projects/ so detection falls back to Generic.
    // Generic still picks up usage from claude-shaped data via the "usage" root key.
    assert_eq!(v["format"], "generic");
}

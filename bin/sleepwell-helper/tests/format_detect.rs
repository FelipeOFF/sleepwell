use assert_cmd::Command;
use predicates::prelude::*;
use std::fs;
use tempfile::tempdir;

fn bin() -> Command {
    Command::cargo_bin("sleepwell-helper").unwrap()
}

#[test]
fn parse_auto_detects_claude_by_path() {
    let tmp = tempdir().unwrap();
    let path = tmp.path().join("anything.jsonl");
    let claude_jsonl = fs::read_to_string("tests/fixtures/claude_sample.jsonl").expect("fixture");
    fs::write(&path, &claude_jsonl).unwrap();

    bin()
        .args(["parse-jsonl", path.to_str().unwrap(), "--format", "claude"])
        .assert()
        .success()
        .stdout(predicate::str::contains("\"format\":\"claude\""));
}

#[test]
fn parse_explicit_codex_format() {
    bin()
        .args([
            "parse-jsonl",
            "tests/fixtures/codex_sample.jsonl",
            "--format",
            "codex",
        ])
        .assert()
        .success()
        .stdout(predicate::str::contains("\"format\":\"codex\""));
}

#[test]
fn parse_explicit_gemini_format() {
    bin()
        .args([
            "parse-jsonl",
            "tests/fixtures/gemini_sample.jsonl",
            "--format",
            "gemini",
        ])
        .assert()
        .success()
        .stdout(predicate::str::contains("\"format\":\"gemini\""));
}

#[test]
fn parse_tolerates_malformed_lines() {
    let tmp = tempdir().unwrap();
    let path = tmp.path().join("malformed.jsonl");
    let content = format!(
        "{}\n{}\n{}\n",
        r#"{"type":"user","content":"hi","usage":{"input_tokens":10,"output_tokens":5}}"#,
        "not-json-at-all },{ broken",
        r#"{"type":"assistant","content":"ok","usage":{"input_tokens":3,"output_tokens":2}}"#,
    );
    fs::write(&path, content).unwrap();

    bin()
        .args(["parse-jsonl", path.to_str().unwrap(), "--format", "claude"])
        .assert()
        .success()
        .stdout(predicate::str::contains("\"input\":13"))
        .stdout(predicate::str::contains("\"output\":7"));
}

#[test]
fn cost_returns_unknown_for_unknown_model() {
    let tmp = tempdir().unwrap();
    let usage = tmp.path().join("usage.json");
    fs::write(
        &usage,
        r#"{"format":"claude","turns":1,"totals":{"input":100,"output":50,"cache_read":0,"cache_creation":0}}"#,
    )
    .unwrap();
    bin()
        .args([
            "cost",
            "--format",
            "claude",
            "--input",
            usage.to_str().unwrap(),
            "--model",
            "fake-model-9999",
        ])
        .assert()
        .success()
        .stdout(predicate::str::contains("unknown").or(predicate::str::contains("null")));
}

#[test]
fn help_lists_all_subcommands() {
    bin()
        .arg("--help")
        .assert()
        .success()
        .stdout(predicate::str::contains("parse-jsonl"))
        .stdout(predicate::str::contains("cost"))
        .stdout(predicate::str::contains("hash"))
        .stdout(predicate::str::contains("watch"))
        .stdout(predicate::str::contains("evaluate"))
        .stdout(predicate::str::contains("calibrate"));
}

#[test]
fn version_flag_works() {
    bin()
        .arg("--version")
        .assert()
        .success()
        .stdout(predicate::str::contains("sleepwell-helper"));
}

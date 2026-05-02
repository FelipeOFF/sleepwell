use assert_cmd::Command;
use serde_json::Value;

fn run_cost(stdin: &str, vendor: &str, model: &str) -> (Value, String, bool) {
    let out = Command::cargo_bin("sleepwell-helper")
        .unwrap()
        .args(["cost", "--format", vendor, "--model", model])
        .write_stdin(stdin)
        .output()
        .unwrap();
    let stdout = String::from_utf8(out.stdout).unwrap();
    let stderr = String::from_utf8(out.stderr).unwrap();
    let v: Value = serde_json::from_str(stdout.trim()).expect("stdout JSON");
    (v, stderr, out.status.success())
}

#[test]
fn computes_known_model() {
    // 1M tokens of each → 3 + 15 + 0.30 + 3.75 = 22.05 USD
    let stdin = r#"{"format":"claude","turns":1,"totals":{"input":1000000,"output":1000000,"cache_read":1000000,"cache_creation":1000000}}"#;
    let (v, _, ok) = run_cost(stdin, "claude", "sonnet-4-5");
    assert!(ok);
    let cost = v["cost_usd"].as_f64().unwrap();
    assert!((cost - 22.05).abs() < 1e-6, "cost was {}", cost);
    assert_eq!(v["model"], "sonnet-4-5");
    assert_eq!(v["vendor"], "claude");
    assert_eq!(v["breakdown"]["input"].as_f64().unwrap(), 3.0);
    assert_eq!(v["breakdown"]["output"].as_f64().unwrap(), 15.0);
}

#[test]
fn unknown_model_returns_null_with_stderr_warning() {
    let stdin = r#"{"totals":{"input":100,"output":100}}"#;
    let (v, stderr, ok) = run_cost(stdin, "claude", "does-not-exist");
    assert!(ok, "exit must be 0 on unknown model");
    assert!(v["cost_usd"].is_null());
    assert_eq!(v["error"], "unknown model");
    assert!(stderr.contains("warning"), "stderr: {}", stderr);
}

#[test]
fn openai_model_no_cache_fields() {
    let stdin = r#"{"totals":{"input":1000000,"output":1000000}}"#;
    let (v, _, ok) = run_cost(stdin, "openai", "gpt-5");
    assert!(ok);
    let cost = v["cost_usd"].as_f64().unwrap();
    // 1.25 + 10.00
    assert!((cost - 11.25).abs() < 1e-6, "cost was {}", cost);
}

use assert_cmd::Command;
use std::fs;
use tempfile::tempdir;

fn copy_fixture_to(workflows_dir: &std::path::Path) {
    fs::create_dir_all(workflows_dir).unwrap();
    let src = std::path::Path::new("tests/fixtures/sample-ci.yml");
    let dst = workflows_dir.join("sample-ci.yml");
    fs::copy(src, &dst).unwrap();
}

#[test]
fn ci_mirror_emits_bash_for_sample_workflow() {
    let dir = tempdir().unwrap();
    let workflows = dir.path().join(".github/workflows");
    copy_fixture_to(&workflows);

    let out = Command::cargo_bin("sleepwell-helper")
        .unwrap()
        .current_dir(dir.path())
        .args(["ci-mirror"])
        .output()
        .unwrap();
    assert!(
        out.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    let s = String::from_utf8(out.stdout).unwrap();

    assert!(s.starts_with("#!/usr/bin/env bash"));
    assert!(s.contains("set -euo pipefail"));
    assert!(s.contains("# === workflow: sample-ci"));
    assert!(s.contains("# --- job: build ---"));
    assert!(s.contains("# --- job: shellcheck ---"));
    // run: lines preserved
    assert!(s.contains("npm ci"));
    assert!(s.contains("npm run lint"));
    assert!(s.contains("npm test"));
    assert!(s.contains("shellcheck scripts/*.sh"));
    // uses: lines become comments
    assert!(s.contains("uses: actions/checkout@v4"));
    assert!(s.contains("uses: actions/setup-node@v4"));
}

#[test]
fn ci_mirror_workflow_filter() {
    let dir = tempdir().unwrap();
    let workflows = dir.path().join(".github/workflows");
    copy_fixture_to(&workflows);
    // second workflow that we will exclude
    fs::write(
        workflows.join("other.yml"),
        "name: other\non: push\njobs:\n  o:\n    steps:\n      - run: echo other-marker\n",
    )
    .unwrap();

    let out = Command::cargo_bin("sleepwell-helper")
        .unwrap()
        .current_dir(dir.path())
        .args(["ci-mirror", "--workflow", "sample-ci"])
        .output()
        .unwrap();
    assert!(out.status.success());
    let s = String::from_utf8(out.stdout).unwrap();
    assert!(s.contains("npm ci"));
    assert!(!s.contains("other-marker"));
}

#[test]
fn ci_mirror_no_workflows_dir_is_ok() {
    let dir = tempdir().unwrap();
    let out = Command::cargo_bin("sleepwell-helper")
        .unwrap()
        .current_dir(dir.path())
        .args(["ci-mirror"])
        .output()
        .unwrap();
    assert!(out.status.success());
    let s = String::from_utf8(out.stdout).unwrap();
    assert!(s.contains("(no .github/workflows directory found)"));
}

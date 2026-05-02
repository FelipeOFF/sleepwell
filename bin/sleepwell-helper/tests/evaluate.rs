use assert_cmd::Command;
use std::io::Write;

fn write_tmp(name: &str, content: &str) -> tempfile::NamedTempFile {
    let mut f = tempfile::Builder::new()
        .prefix("sw-eval-")
        .suffix(name)
        .tempfile()
        .unwrap();
    f.write_all(content.as_bytes()).unwrap();
    f
}

#[test]
fn evaluate_pass_clean() {
    let state = write_tmp(
        ".json",
        r#"{"last_outcome":"PASS","last_commit_msg":"feat: novo handler"}"#,
    );
    let diff = write_tmp(
        ".txt",
        " 2 files changed, 30 insertions(+), 15 deletions(-)\n",
    );
    let notes = write_tmp(".md", "implementação ok");

    let out = Command::cargo_bin("sleepwell-helper")
        .unwrap()
        .args([
            "evaluate",
            "--state",
            state.path().to_str().unwrap(),
            "--diff-stat",
            diff.path().to_str().unwrap(),
            "--last-notes",
            notes.path().to_str().unwrap(),
        ])
        .output()
        .unwrap();
    assert!(
        out.status.success(),
        "stderr={}",
        String::from_utf8_lossy(&out.stderr)
    );
    let s = String::from_utf8(out.stdout).unwrap();
    assert!(s.contains("\"rating\":5"), "got {}", s);
    assert!(s.contains("\"course_correct\":false"));
}

#[test]
fn evaluate_fail_with_churn_and_todo() {
    let state = write_tmp(
        ".json",
        r#"{"last_outcome":"FAIL","last_commit_msg":"wip"}"#,
    );
    let diff = write_tmp(
        ".txt",
        " 4 files changed, 600 insertions(+), 50 deletions(-)\n",
    );
    let notes = write_tmp(".md", "TODO: revisitar layout");

    let out = Command::cargo_bin("sleepwell-helper")
        .unwrap()
        .args([
            "evaluate",
            "--state",
            state.path().to_str().unwrap(),
            "--diff-stat",
            diff.path().to_str().unwrap(),
            "--last-notes",
            notes.path().to_str().unwrap(),
        ])
        .output()
        .unwrap();
    assert!(out.status.success());
    let s = String::from_utf8(out.stdout).unwrap();
    assert!(s.contains("\"rating\":1"), "got {}", s);
    assert!(s.contains("\"course_correct\":true"));
}

#[test]
fn evaluate_no_inputs_neutral() {
    let out = Command::cargo_bin("sleepwell-helper")
        .unwrap()
        .args(["evaluate"])
        .output()
        .unwrap();
    assert!(out.status.success());
    let s = String::from_utf8(out.stdout).unwrap();
    assert!(s.contains("\"rating\":3"), "got {}", s);
    assert!(s.contains("\"course_correct\":false"));
}

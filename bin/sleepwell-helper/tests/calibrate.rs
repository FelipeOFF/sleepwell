use assert_cmd::Command;
use std::fs;
use std::process::Command as PCommand;

fn write_state(dir: &std::path::Path, name: &str, intent: &str, branch: &str) {
    let sub = dir.join(name);
    fs::create_dir_all(&sub).unwrap();
    let body = format!(
        r#"{{"intent":"{}","branch":"{}"}}"#,
        intent.replace('"', "\\\""),
        branch
    );
    fs::write(sub.join("state.json"), body).unwrap();
}

#[test]
fn calibrate_empty_archive_emits_defaults() {
    let tmp = tempfile::tempdir().unwrap();
    let archive = tmp.path().join("archive");
    fs::create_dir_all(&archive).unwrap();

    let out = Command::cargo_bin("sleepwell-helper")
        .unwrap()
        .args([
            "calibrate",
            "--archive",
            archive.to_str().unwrap(),
            "--repo",
            tmp.path().to_str().unwrap(),
            "--base-branch",
            "main",
        ])
        .output()
        .unwrap();
    assert!(
        out.status.success(),
        "stderr={}",
        String::from_utf8_lossy(&out.stderr)
    );
    let s = String::from_utf8(out.stdout).unwrap();
    assert!(s.contains("\"n_runs\":0"), "got {}", s);
    assert!(s.contains("\"overall\":0.0"));
}

#[test]
fn calibrate_with_synthetic_runs() {
    // Build a repo with merged refactor branches + an unmerged feat branch.
    // We keep the archive directory OUTSIDE the working tree so checkouts
    // don't move state.json files around.
    let outer = tempfile::tempdir().unwrap();
    let repo = outer.path().join("repo");
    let archive = outer.path().join("archive");
    fs::create_dir_all(&repo).unwrap();
    fs::create_dir_all(&archive).unwrap();

    let g = |args: &[&str]| {
        let s = PCommand::new("git")
            .args(args)
            .current_dir(&repo)
            .status()
            .unwrap();
        assert!(s.success(), "git {:?}", args);
    };
    g(&["init", "-q", "-b", "main"]);
    g(&["config", "user.email", "t@t"]);
    g(&["config", "user.name", "t"]);
    fs::write(repo.join("README.md"), "x").unwrap();
    g(&["add", "."]);
    g(&["commit", "-qm", "init"]);

    // Three merged refactor branches.
    for i in 0..3 {
        let br = format!("refactor/x{}", i);
        g(&["checkout", "-qb", &br]);
        fs::write(repo.join(format!("f{}.txt", i)), "y").unwrap();
        g(&["add", "."]);
        g(&["commit", "-qm", "x"]);
        g(&["checkout", "-q", "main"]);
        g(&["merge", "-q", "--no-ff", "-m", "merge", &br]);
        write_state(&archive, &format!("run{}", i), &format!("refactor: x{}", i), &br);
    }

    // One unmerged feat branch.
    g(&["checkout", "-qb", "feat/y"]);
    fs::write(repo.join("y.txt"), "y").unwrap();
    g(&["add", "."]);
    g(&["commit", "-qm", "y"]);
    g(&["checkout", "-q", "main"]);
    write_state(&archive, "run3", "feat: y", "feat/y");

    let out = Command::cargo_bin("sleepwell-helper")
        .unwrap()
        .args([
            "calibrate",
            "--archive",
            archive.to_str().unwrap(),
            "--repo",
            repo.to_str().unwrap(),
            "--base-branch",
            "main",
        ])
        .output()
        .unwrap();
    assert!(
        out.status.success(),
        "stderr={}",
        String::from_utf8_lossy(&out.stderr)
    );
    let s = String::from_utf8(out.stdout).unwrap();
    assert!(s.contains("\"n_runs\":4"), "got {}", s);
    assert!(s.contains("\"refactor\":1.0"), "got {}", s);
    assert!(s.contains("\"trusted\":[\"refactor\"]"), "got {}", s);
}

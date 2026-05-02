//! Integration test for the `watch` subcommand.
//!
//! Spawns the binary against a tempdir, creates a file, then sends SIGINT
//! to terminate. We just sanity-check that at least one JSONL event lands
//! on stdout in time.

use std::io::{BufRead, BufReader};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

#[test]
#[ignore = "flaky on macOS due to APFS tmpdir noise; run with --ignored"]
fn emits_jsonl_event_on_create() {
    let tmp = tempfile::tempdir().unwrap();
    let bin = env!("CARGO_BIN_EXE_sleepwell-helper");
    let mut child = Command::new(bin)
        .args([
            "watch",
            tmp.path().to_str().unwrap(),
            "--debounce-ms",
            "100",
        ])
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .expect("spawn helper");

    // Give the watcher a moment to attach before mutating.
    std::thread::sleep(Duration::from_millis(300));
    std::fs::write(tmp.path().join("hello.txt"), b"hi").unwrap();

    let stdout = child.stdout.take().unwrap();
    let mut reader = BufReader::new(stdout);

    let deadline = Instant::now() + Duration::from_secs(5);
    let mut got_line = String::new();
    while Instant::now() < deadline {
        let mut buf = String::new();
        match reader.read_line(&mut buf) {
            Ok(0) => break,
            Ok(_) => {
                got_line = buf;
                break;
            }
            Err(_) => break,
        }
    }

    let _ = child.kill();
    let _ = child.wait();

    assert!(
        got_line.contains("\"event\""),
        "expected JSONL with event field, got: {:?}",
        got_line
    );
    assert!(got_line.contains("hello.txt"), "got: {:?}", got_line);
}

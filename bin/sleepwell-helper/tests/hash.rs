use assert_cmd::Command;

#[test]
fn hash_positional_arg() {
    Command::cargo_bin("sleepwell-helper")
        .unwrap()
        .args(["hash", "foo"])
        .assert()
        .success()
        .stdout("04e0bb39f30b1a3feb89f536c93be15055482df748674b00d26e5a75777702e9\n");
}

#[test]
fn hash_multiple_positional() {
    let out = Command::cargo_bin("sleepwell-helper")
        .unwrap()
        .args(["hash", "foo", "bar"])
        .output()
        .unwrap();
    assert!(out.status.success());
    let s = String::from_utf8(out.stdout).unwrap();
    let lines: Vec<&str> = s.lines().collect();
    assert_eq!(lines.len(), 2);
    assert_eq!(
        lines[0],
        "04e0bb39f30b1a3feb89f536c93be15055482df748674b00d26e5a75777702e9"
    );
    assert_eq!(lines[1].len(), 64);
}

#[test]
fn hash_stdin() {
    let out = Command::cargo_bin("sleepwell-helper")
        .unwrap()
        .arg("hash")
        .write_stdin("foo\nbar\n")
        .output()
        .unwrap();
    assert!(out.status.success());
    let s = String::from_utf8(out.stdout).unwrap();
    let lines: Vec<&str> = s.lines().collect();
    assert_eq!(lines.len(), 2);
    assert_eq!(
        lines[0],
        "04e0bb39f30b1a3feb89f536c93be15055482df748674b00d26e5a75777702e9"
    );
}

//! `watch` subcommand: filesystem watcher that emits JSONL events.
//!
//! Uses `notify` + `notify-debouncer-mini` to coalesce rapid filesystem
//! events. Each emitted line is a JSON object of the form:
//!
//! ```json
//! {"event":"created|modified|removed","path":"...","ts":"<RFC3339>"}
//! ```
//!
//! Manual smoke test:
//! ```sh
//! mkdir -p /tmp/sw-watch
//! sleepwell-helper watch /tmp/sw-watch --debounce-ms 200 &
//! touch /tmp/sw-watch/a; sleep 0.5; rm /tmp/sw-watch/a
//! ```

use anyhow::{Context, Result};
use chrono::Utc;
use clap::Args;
use notify::RecursiveMode;
use notify_debouncer_mini::new_debouncer;
use serde::Serialize;
use std::io::Write;
use std::path::PathBuf;
use std::sync::mpsc;
use std::time::Duration;

#[derive(Debug, Args)]
pub struct WatchArgs {
    /// Directory to watch.
    pub path: PathBuf,
    /// Debounce window in milliseconds (default 500).
    #[arg(long, default_value_t = 500)]
    pub debounce_ms: u64,
    /// Watch recursively (default true).
    #[arg(long, default_value_t = true, action = clap::ArgAction::Set)]
    pub recursive: bool,
}

#[derive(Debug, Serialize)]
struct EventLine<'a> {
    event: &'a str,
    path: String,
    ts: String,
}

pub fn run(args: WatchArgs) -> Result<()> {
    let (tx, rx) = mpsc::channel();

    let mode = if args.recursive {
        RecursiveMode::Recursive
    } else {
        RecursiveMode::NonRecursive
    };

    let mut debouncer =
        new_debouncer(Duration::from_millis(args.debounce_ms), tx).context("init debouncer")?;
    debouncer
        .watcher()
        .watch(&args.path, mode)
        .with_context(|| format!("watch path {:?}", args.path))?;

    // Ctrl+C: install handler to break the loop cleanly via shutdown channel.
    let (stop_tx, stop_rx) = mpsc::channel::<()>();
    ctrlc::set_handler(move || {
        let _ = stop_tx.send(());
    })
    .context("install ctrl+c handler")?;

    let stdout = std::io::stdout();
    loop {
        match rx.recv_timeout(Duration::from_millis(200)) {
            Ok(res) => {
                let events = match res {
                    Ok(evts) => evts,
                    Err(errs) => {
                        eprintln!("watch error: {:?}", errs);
                        continue;
                    }
                };
                let ts = Utc::now().to_rfc3339();
                let mut out = stdout.lock();
                for e in events {
                    let kind = classify(&e);
                    let ev = EventLine {
                        event: kind,
                        path: e.path.to_string_lossy().to_string(),
                        ts: ts.clone(),
                    };
                    writeln!(out, "{}", serde_json::to_string(&ev)?)?;
                }
                out.flush()?;
            }
            Err(mpsc::RecvTimeoutError::Timeout) => {
                if stop_rx.try_recv().is_ok() {
                    break;
                }
            }
            Err(mpsc::RecvTimeoutError::Disconnected) => break,
        }
    }
    Ok(())
}

fn classify(e: &notify_debouncer_mini::DebouncedEvent) -> &'static str {
    use notify_debouncer_mini::DebouncedEventKind;
    // The mini debouncer collapses events; infer create/modify/remove by
    // checking the path's current existence and birth/modify timestamps.
    match e.kind {
        DebouncedEventKind::Any | DebouncedEventKind::AnyContinuous => {
            if !e.path.exists() {
                "removed"
            } else if e
                .path
                .metadata()
                .ok()
                .and_then(|m| m.created().ok().zip(m.modified().ok()))
                .map(|(c, m)| {
                    m.duration_since(c)
                        .map(|d| d.as_millis() < 50)
                        .unwrap_or(false)
                })
                .unwrap_or(false)
            {
                "created"
            } else {
                "modified"
            }
        }
        _ => "modified",
    }
}

//! The `agentpet hook --agent <kind>` command, run by each agent's hook. It
//! reads the agent's JSON payload on stdin, extracts the essentials, and POSTs
//! them to the running app's localhost listener. ALWAYS exits 0 (some agents,
//! e.g. Copilot PreToolUse, are fail-closed , a non-zero exit would block the
//! user's tools). If the app isn't running, the POST simply fails silently.

use serde_json::Value;
use std::io::{Read, Write};
use std::net::TcpStream;

pub fn run_hook(args: &[String]) {
    let agent = parse_agent(args).unwrap_or_else(|| "unknown".into());

    let mut stdin_buf = String::new();
    let _ = std::io::stdin().read_to_string(&mut stdin_buf);
    let v: Value = serde_json::from_str(&stdin_buf).unwrap_or(Value::Null);

    let event = v.get("hook_event_name").and_then(|x| x.as_str()).unwrap_or("");
    let session = v.get("session_id").and_then(|x| x.as_str()).unwrap_or("");
    let project = v.get("cwd").and_then(|x| x.as_str()).unwrap_or("");
    let message = v.get("message").and_then(|x| x.as_str()).unwrap_or("");

    // Nothing useful to report -> exit cleanly (never block the agent).
    if session.is_empty() && event.is_empty() {
        std::process::exit(0);
    }

    let payload = serde_json::json!({
        "agent": agent, "event": event, "session": session,
        "project": project, "message": message,
    })
    .to_string();

    let _ = post(&payload);
    std::process::exit(0);
}

fn parse_agent(args: &[String]) -> Option<String> {
    let mut it = args.iter();
    while let Some(a) = it.next() {
        if a == "--agent" {
            return it.next().cloned();
        }
    }
    None
}

/// Minimal HTTP POST to the local listener (no extra deps).
fn post(body: &str) -> std::io::Result<()> {
    let mut stream = TcpStream::connect(("127.0.0.1", crate::server::HOOK_PORT))?;
    let req = format!(
        "POST /event HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        body.len(),
        body
    );
    stream.write_all(req.as_bytes())?;
    let mut _resp = String::new();
    let _ = stream.read_to_string(&mut _resp);
    Ok(())
}

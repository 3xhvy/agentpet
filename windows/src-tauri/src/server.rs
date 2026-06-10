//! A tiny localhost HTTP listener. The `agentpet hook` CLI (run by each agent's
//! hook) POSTs an event here; we map it to a pet state and emit a Tauri event to
//! the pet window. Mirrors the macOS app's unix-socket daemon, but cross-platform.

use serde_json::Value;
use std::io::Read;
use tauri::{AppHandle, Emitter};

pub const HOOK_PORT: u16 = 47628;

pub fn start(app: AppHandle) {
    std::thread::spawn(move || {
        let server = match tiny_http::Server::http(("127.0.0.1", HOOK_PORT)) {
            Ok(s) => s,
            Err(_) => return, // another instance owns the port
        };
        for mut req in server.incoming_requests() {
            let mut body = String::new();
            let _ = req.as_reader().read_to_string(&mut body);
            handle_event(&app, &body);
            let _ = req.respond(tiny_http::Response::from_string("ok"));
        }
    });
}

fn handle_event(app: &AppHandle, body: &str) {
    let Ok(v) = serde_json::from_str::<Value>(body) else { return };
    let agent = v.get("agent").and_then(|x| x.as_str()).unwrap_or("unknown");
    let event = v.get("event").and_then(|x| x.as_str()).unwrap_or("");
    let session = v.get("session").and_then(|x| x.as_str()).unwrap_or("");
    let project = v.get("project").and_then(|x| x.as_str()).unwrap_or("");
    let message = v.get("message").and_then(|x| x.as_str()).unwrap_or("");

    if crate::statemap::is_session_end(agent, event) {
        let _ = app.emit_to("pet", "agent-end", session);
        return;
    }
    let Some(state) = crate::statemap::state(agent, event) else { return };
    let payload = serde_json::json!({
        "agent": agent, "state": state, "session": session,
        "project": project, "message": message,
    });
    let _ = app.emit_to("pet", "agent-event", payload);
}

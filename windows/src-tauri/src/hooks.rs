//! Writes/removes AgentPet's hook entries in each agent's config, using Windows
//! paths (%USERPROFILE%\.claude\settings.json, ...). Ported from the macOS app's
//! AgentHooks + HookInstaller. Our entries are identified by their command
//! string so install is idempotent and foreign hooks are never touched.

use serde::Serialize;
use serde_json::{json, Map, Value};
use std::path::PathBuf;

#[derive(Serialize, Clone)]
pub struct AgentInfo {
    pub kind: String,
    pub display_name: String,
    pub installed: bool,
    pub note: Option<String>,
}

#[derive(Clone, Copy, PartialEq)]
enum Style {
    ClaudeNested,
    CursorFlat,
}

struct Spec {
    style: Style,
    rel_path: &'static [&'static str], // path under home
    events: &'static [&'static str],
}

fn spec(kind: &str) -> Option<Spec> {
    Some(match kind {
        "claude" => Spec {
            style: Style::ClaudeNested,
            rel_path: &[".claude", "settings.json"],
            events: &["SessionStart", "UserPromptSubmit", "PreToolUse", "Notification", "Stop", "SubagentStop", "SessionEnd"],
        },
        "codex" => Spec {
            style: Style::ClaudeNested,
            rel_path: &[".codex", "hooks.json"],
            events: &["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "Stop", "SubagentStop"],
        },
        "gemini" => Spec {
            style: Style::ClaudeNested,
            rel_path: &[".gemini", "settings.json"],
            events: &["SessionStart", "BeforeAgent", "BeforeTool", "AfterTool", "Notification", "AfterAgent", "SessionEnd"],
        },
        "cursor" => Spec {
            style: Style::CursorFlat,
            rel_path: &[".cursor", "hooks.json"],
            events: &["sessionStart", "beforeSubmitPrompt", "preToolUse", "stop", "subagentStop", "sessionEnd"],
        },
        "copilot" => Spec {
            style: Style::CursorFlat,
            rel_path: &[".copilot", "hooks", "agentpet.json"],
            events: &["SessionStart", "UserPromptSubmit", "PostToolUse", "Stop"],
        },
        _ => return None,
    })
}

pub fn catalog() -> Vec<AgentInfo> {
    let entries: &[(&str, &str, Option<&str>)] = &[
        ("claude", "Claude Code", None),
        ("codex", "Codex", Some("After enabling, run /hooks in Codex and Trust the AgentPet hook")),
        ("gemini", "Gemini CLI", None),
        ("cursor", "Cursor", None),
        ("copilot", "GitHub Copilot", Some("Copilot CLI only (~/.copilot/hooks)")),
    ];
    entries
        .iter()
        .map(|(kind, name, note)| AgentInfo {
            kind: kind.to_string(),
            display_name: name.to_string(),
            installed: is_installed(kind),
            note: note.map(|s| s.to_string()),
        })
        .collect()
}

fn config_path(kind: &str) -> Option<PathBuf> {
    let home = dirs::home_dir()?;
    let s = spec(kind)?;
    let mut p = home;
    for part in s.rel_path {
        p.push(part);
    }
    Some(p)
}

fn hook_command() -> String {
    let exe = std::env::current_exe()
        .map(|p| p.to_string_lossy().into_owned())
        .unwrap_or_else(|_| "agentpet".into());
    format!("\"{}\" hook --agent", exe)
}

fn full_command(kind: &str) -> String {
    format!("{} {}", hook_command(), kind)
}

fn is_ours(cmd: &str) -> bool {
    let l = cmd.to_lowercase();
    l.contains("agentpet") && l.contains("hook")
}

fn read_json(path: &PathBuf) -> Value {
    std::fs::read_to_string(path)
        .ok()
        .and_then(|s| if s.trim().is_empty() { None } else { serde_json::from_str(&s).ok() })
        .unwrap_or_else(|| json!({}))
}

fn write_json(path: &PathBuf, v: &Value) -> std::io::Result<()> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    std::fs::write(path, serde_json::to_string_pretty(v).unwrap_or_default())
}

pub fn is_installed(kind: &str) -> bool {
    let (Some(path), Some(s)) = (config_path(kind), spec(kind)) else { return false };
    let v = read_json(&path);
    let hooks = match v.get("hooks").and_then(|h| h.as_object()) {
        Some(h) => h,
        None => return false,
    };
    for event in s.events {
        if let Some(arr) = hooks.get(*event).and_then(|a| a.as_array()) {
            let found = arr.iter().any(|entry| entry_is_ours(s.style, entry));
            if found {
                return true;
            }
        }
    }
    false
}

fn entry_is_ours(style: Style, entry: &Value) -> bool {
    match style {
        Style::ClaudeNested => entry
            .get("hooks")
            .and_then(|h| h.as_array())
            .map(|inner| {
                inner.iter().any(|h| h.get("command").and_then(|c| c.as_str()).map(is_ours).unwrap_or(false))
            })
            .unwrap_or(false),
        Style::CursorFlat => entry.get("command").and_then(|c| c.as_str()).map(is_ours).unwrap_or(false),
    }
}

pub fn toggle(kind: &str) -> Result<bool, String> {
    if is_installed(kind) {
        uninstall(kind).map_err(|e| e.to_string())?;
        Ok(false)
    } else {
        install(kind).map_err(|e| e.to_string())?;
        Ok(true)
    }
}

fn install(kind: &str) -> std::io::Result<()> {
    let (Some(path), Some(s)) = (config_path(kind), spec(kind)) else {
        return Err(std::io::Error::new(std::io::ErrorKind::Other, "unknown agent"));
    };
    let mut v = read_json(&path);
    let cmd = full_command(kind);
    // Refuse to rewrite a file we can't read as a JSON object (don't clobber it).
    let Some(obj) = v.as_object_mut() else {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            format!("{} is not a JSON object; fix or remove it and try again", path.display()),
        ));
    };
    if s.style == Style::CursorFlat {
        obj.entry("version").or_insert(json!(1));
    }
    // Ensure "hooks" is an object before we index into it.
    if !obj.get("hooks").map_or(false, |h| h.is_object()) {
        obj.insert("hooks".to_string(), json!({}));
    }
    let hooks = obj.get_mut("hooks").and_then(|h| h.as_object_mut()).unwrap();
    for event in s.events {
        let mut kept: Vec<Value> = hooks
            .get(*event)
            .and_then(|a| a.as_array())
            .map(|a| a.iter().filter(|e| !entry_is_ours(s.style, e)).cloned().collect())
            .unwrap_or_default();
        match s.style {
            Style::ClaudeNested => kept.push(json!({ "hooks": [{ "type": "command", "command": cmd }] })),
            Style::CursorFlat => kept.push(json!({ "command": cmd, "type": "command" })),
        }
        hooks.insert((*event).to_string(), Value::Array(kept));
    }
    write_json(&path, &v)?;
    if kind == "codex" {
        enable_codex_hooks();
    }
    Ok(())
}

fn uninstall(kind: &str) -> std::io::Result<()> {
    let (Some(path), Some(s)) = (config_path(kind), spec(kind)) else { return Ok(()) };
    // Copilot uses a dedicated file we own; just delete it.
    if kind == "copilot" {
        let _ = std::fs::remove_file(&path);
        return Ok(());
    }
    let mut v = read_json(&path);
    let Some(obj) = v.as_object_mut() else { return Ok(()) };
    if let Some(hooks) = obj.get_mut("hooks").and_then(|h| h.as_object_mut()) {
        let events: Vec<String> = s.events.iter().map(|e| e.to_string()).collect();
        for event in &events {
            if let Some(arr) = hooks.get(event).and_then(|a| a.as_array()) {
                let kept: Vec<Value> = arr.iter().filter(|e| !entry_is_ours(s.style, e)).cloned().collect();
                if kept.is_empty() {
                    hooks.remove(event);
                } else {
                    hooks.insert(event.clone(), Value::Array(kept));
                }
            }
        }
        let empty = hooks.is_empty();
        if empty {
            obj.remove("hooks");
        }
    }
    write_json(&path, &v)
}

/// Ensure `[features] hooks = true` in ~/.codex/config.toml (modern key; the
/// `codex_hooks` alias is ignored by recent Codex). Plain string edit so we
/// don't pull in a TOML parser and never touch unrelated keys.
fn enable_codex_hooks() {
    let Some(home) = dirs::home_dir() else { return };
    let path = home.join(".codex").join("config.toml");
    let text = std::fs::read_to_string(&path).unwrap_or_default();
    let already = text.lines().any(|l| {
        let c = l.trim().replace(' ', "");
        !c.starts_with('#') && c.starts_with("hooks=true")
    });
    if already {
        return;
    }
    let updated = if let Some(idx) = text.lines().position(|l| l.trim() == "[features]") {
        let mut lines: Vec<String> = text.lines().map(|s| s.to_string()).collect();
        lines.insert(idx + 1, "hooks = true".into());
        lines.join("\n")
    } else {
        let mut t = text;
        if !t.is_empty() && !t.ends_with('\n') {
            t.push('\n');
        }
        t.push_str("\n[features]\nhooks = true\n");
        t
    };
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let _ = std::fs::write(&path, updated);
}

#[allow(dead_code)]
fn _unused(_: &Map<String, Value>) {}

// Prevents an extra console window on Windows release builds.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    let args: Vec<String> = std::env::args().collect();
    // Invoked by an agent's hook: `agentpet hook --agent <kind>` (reads stdin).
    if args.get(1).map(String::as_str) == Some("hook") {
        agentpet_lib::cli::run_hook(&args[2..]);
        return;
    }
    agentpet_lib::run();
}

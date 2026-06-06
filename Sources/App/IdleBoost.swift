import Foundation

enum IdleBoost {
    static let lines = [
        "Let's grill some bugs.",
        "I miss you. Ship something for me.",
        "No agents running. The keyboard is getting suspicious.",
        "Hydrate, stretch, then break production responsibly.",
        "Your codebase called. It wants a tiny miracle.",
        "Idle mode activated. Motivation cache is warm.",
        "Push a little commit. As a treat.",
        "The build is quiet. Too quiet.",
        "Give me a task and I'll pretend I am calm.",
        "Nothing running. Time to cook something spicy.",
        "Open a branch. Let chaos become architecture.",
        "Your future self requests fewer TODOs.",
    ]

    static func line(at date: Date = Date()) -> String {
        let minute = max(0, Int(date.timeIntervalSince1970 / 60))
        return lines[minute % lines.count]
    }
}

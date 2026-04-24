import Foundation

class HookInstaller {
    private let settingsPath: String

    /// Hooks to install. Each event type gets its own shell command that appends
    /// a JSON line to ~/.claude/desktophelper/events.jsonl
    private let hooksToInstall: [(eventName: String, command: String)] = [
        (
            "Stop",
            "echo '{\"event\":\"Stop\",\"session\":\"'\"$CLAUDE_SESSION_ID\"'\",\"cwd\":\"'\"$PWD\"'\",\"summary\":\"Task completed\"}' >> ~/.claude/desktophelper/events.jsonl"
        ),
        (
            "Notification",
            "echo '{\"event\":\"Notification\",\"session\":\"'\"$CLAUDE_SESSION_ID\"'\",\"cwd\":\"'\"$PWD\"'\",\"summary\":\"Waiting for input\"}' >> ~/.claude/desktophelper/events.jsonl"
        ),
        (
            "UserPromptSubmit",
            "echo '{\"event\":\"UserPromptSubmit\",\"session\":\"'\"$CLAUDE_SESSION_ID\"'\",\"cwd\":\"'\"$PWD\"'\",\"summary\":\"User prompted\"}' >> ~/.claude/desktophelper/events.jsonl"
        ),
    ]

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        settingsPath = "\(home)/.claude/settings.json"
    }

    func ensureHooksInstalled() -> Bool {
        guard let data = FileManager.default.contents(atPath: settingsPath),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            print("[HookInstaller] Could not read settings.json")
            return false
        }

        var hooks = json["hooks"] as? [String: Any] ?? [:]
        var changed = false

        for (eventName, command) in hooksToInstall {
            var eventHooks = hooks[eventName] as? [[String: Any]] ?? []

            let alreadyInstalled = eventHooks.contains { hookGroup in
                guard let innerHooks = hookGroup["hooks"] as? [[String: Any]] else { return false }
                return innerHooks.contains { hook in
                    (hook["command"] as? String)?.contains("desktophelper/events.jsonl") == true &&
                    (hook["command"] as? String)?.contains("\"event\":\"\(eventName)\"") == true
                }
            }

            if alreadyInstalled { continue }

            let ourHook: [String: Any] = ["type": "command", "command": command]

            if eventHooks.isEmpty {
                eventHooks = [["hooks": [ourHook]]]
            } else {
                var firstGroup = eventHooks[0]
                var innerHooks = firstGroup["hooks"] as? [[String: Any]] ?? []
                innerHooks.append(ourHook)
                firstGroup["hooks"] = innerHooks
                eventHooks[0] = firstGroup
            }

            hooks[eventName] = eventHooks
            changed = true
            print("[HookInstaller] Installed \(eventName) hook")
        }

        if !changed {
            print("[HookInstaller] All hooks already installed")
            return true
        }

        json["hooks"] = hooks

        do {
            let newData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try newData.write(to: URL(fileURLWithPath: settingsPath))
            print("[HookInstaller] Hooks installed successfully")
            return true
        } catch {
            print("[HookInstaller] Failed to write settings: \(error)")
            return false
        }
    }
}

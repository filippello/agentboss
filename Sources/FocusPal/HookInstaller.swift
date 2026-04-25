import Foundation

class HookInstaller {
    private let settingsPath: String

    /// Hooks to install. Each event type gets its own shell command that appends
    /// a JSON line to ~/.claude/focuspal/events.jsonl
    private let hooksToInstall: [(eventName: String, command: String)] = [
        (
            "Stop",
            "echo '{\"event\":\"Stop\",\"session\":\"'\"$CLAUDE_SESSION_ID\"'\",\"cwd\":\"'\"$PWD\"'\",\"summary\":\"Task completed\"}' >> ~/.claude/focuspal/events.jsonl"
        ),
        (
            "Notification",
            "echo '{\"event\":\"Notification\",\"session\":\"'\"$CLAUDE_SESSION_ID\"'\",\"cwd\":\"'\"$PWD\"'\",\"summary\":\"Waiting for input\"}' >> ~/.claude/focuspal/events.jsonl"
        ),
        (
            "UserPromptSubmit",
            "echo '{\"event\":\"UserPromptSubmit\",\"session\":\"'\"$CLAUDE_SESSION_ID\"'\",\"cwd\":\"'\"$PWD\"'\",\"summary\":\"User prompted\"}' >> ~/.claude/focuspal/events.jsonl"
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

        // Legacy cleanup: prior versions wrote events to ~/.claude/desktophelper/.
        // Strip those hook entries so we don't double-fire after rename.
        for (eventName, _) in hooksToInstall {
            guard var eventHooks = hooks[eventName] as? [[String: Any]] else { continue }
            for groupIndex in eventHooks.indices {
                guard var inner = eventHooks[groupIndex]["hooks"] as? [[String: Any]] else { continue }
                let originalCount = inner.count
                inner.removeAll { hook in
                    (hook["command"] as? String)?.contains("desktophelper/events.jsonl") == true
                }
                if inner.count != originalCount {
                    eventHooks[groupIndex]["hooks"] = inner
                    changed = true
                    print("[HookInstaller] Removed legacy desktophelper hook from \(eventName)")
                }
            }
            hooks[eventName] = eventHooks
        }

        for (eventName, command) in hooksToInstall {
            var eventHooks = hooks[eventName] as? [[String: Any]] ?? []

            let alreadyInstalled = eventHooks.contains { hookGroup in
                guard let innerHooks = hookGroup["hooks"] as? [[String: Any]] else { return false }
                return innerHooks.contains { hook in
                    (hook["command"] as? String)?.contains("focuspal/events.jsonl") == true &&
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

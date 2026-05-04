import Foundation

/// One command sent in by the `/focuspal` slash command.
///
/// Two wire formats are accepted, both decoded into the same struct:
/// 1. New (preferred):  `{"raw":"<verbatim $ARGUMENTS>"}`
/// 2. Legacy:           `{"command":"<name>","args":"<rest>","ts":<unix>}`
///
/// We split on first whitespace from `raw` ourselves on the Swift side —
/// Claude Code now rejects SKILL.md bash that contains parameter
/// expansion (`${a%% *}`, `$(...)`, etc.) under "Contains expansion",
/// so doing the split server-side here keeps the slash command's bash
/// trivially simple.
struct RemoteCommand: Codable {
    let command: String
    let args: String

    private enum CodingKeys: String, CodingKey {
        case command, args, raw
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let raw = try c.decodeIfPresent(String.self, forKey: .raw) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let space = trimmed.firstIndex(where: { $0.isWhitespace }) {
                self.command = String(trimmed[..<space]).lowercased()
                self.args = String(trimmed[trimmed.index(after: space)...])
                    .trimmingCharacters(in: .whitespaces)
            } else {
                self.command = trimmed.lowercased()
                self.args = ""
            }
        } else {
            self.command = (try c.decodeIfPresent(String.self, forKey: .command) ?? "").lowercased()
            self.args = try c.decodeIfPresent(String.self, forKey: .args) ?? ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(command, forKey: .command)
        try c.encode(args, forKey: .args)
    }
}

protocol CommandChannelMonitorDelegate: AnyObject {
    func commandChannelDidReceive(_ command: RemoteCommand)
}

/// Watches `~/.claude/focuspal/commands.jsonl` for slash-command-driven
/// requests from Claude Code. Sister of `ClaudeCodeMonitor` — same polling
/// pattern, different file, different payload type.
final class CommandChannelMonitor {
    weak var delegate: CommandChannelMonitorDelegate?

    private let commandsFile: String
    private var lastFileSize: UInt64 = 0
    private var pollTimer: Timer?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let commandsDir = "\(home)/.claude/focuspal"
        commandsFile = "\(commandsDir)/commands.jsonl"
        setup()
    }

    private func setup() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: (commandsFile as NSString).deletingLastPathComponent) {
            try? fm.createDirectory(atPath: (commandsFile as NSString).deletingLastPathComponent,
                                    withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: commandsFile) {
            fm.createFile(atPath: commandsFile, contents: nil)
        }
        if let attrs = try? fm.attributesOfItem(atPath: commandsFile),
           let size = attrs[.size] as? UInt64 {
            lastFileSize = size
        }

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForNewCommands()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func checkForNewCommands() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: commandsFile),
              let currentSize = attrs[.size] as? UInt64,
              currentSize > lastFileSize,
              let handle = FileHandle(forReadingAtPath: commandsFile)
        else { return }

        handle.seek(toFileOffset: lastFileSize)
        let data = handle.readDataToEndOfFile()
        handle.closeFile()
        lastFileSize = currentSize

        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }

        let decoder = JSONDecoder()
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            // Tolerant parsing: when the SKILL.md preprocessing fires we get
            // a JSON line. But Claude sometimes invokes /focuspal as a plain
            // prompt instead of running the skill — in that mode it appends
            // a bare line like `pomodoro` (or `""`) via its own bash. Accept
            // both shapes so the frog reacts either way.
            if line.hasPrefix("{"),
               let lineData = line.data(using: .utf8),
               let cmd = try? decoder.decode(RemoteCommand.self, from: lineData) {
                delegate?.commandChannelDidReceive(cmd)
            } else {
                // Strip surrounding quotes (Claude often writes `echo ""`,
                // which lands as a literal `""` token if the redirection
                // unquotes it on the way out).
                let unquoted = line.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                let synthetic = ["raw": unquoted]
                if let bytes = try? JSONSerialization.data(withJSONObject: synthetic),
                   let cmd = try? decoder.decode(RemoteCommand.self, from: bytes) {
                    delegate?.commandChannelDidReceive(cmd)
                }
            }
        }
    }

    deinit {
        pollTimer?.invalidate()
    }
}

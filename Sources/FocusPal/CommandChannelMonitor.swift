import Foundation

/// One command sent in by the `/focuspal` slash command.
/// Schema: `{"command":"<name>", "args":"<rest of $ARGUMENTS>", "ts":<unix>}`.
struct RemoteCommand: Codable {
    let command: String
    let args: String?
    let ts: Int64?
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
        for line in text.components(separatedBy: .newlines) where !line.isEmpty {
            guard let lineData = line.data(using: .utf8),
                  let cmd = try? decoder.decode(RemoteCommand.self, from: lineData)
            else { continue }
            delegate?.commandChannelDidReceive(cmd)
        }
    }

    deinit {
        pollTimer?.invalidate()
    }
}

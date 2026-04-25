import AppKit
import Foundation

struct ClaudeCodeEvent: Codable {
    let event: String
    let timestamp: Int64?
    let session: String?
    let cwd: String?
    let summary: String?
}

protocol ClaudeCodeMonitorDelegate: AnyObject {
    func claudeCodeDidComplete(event: ClaudeCodeEvent)
    func claudeCodeAwaitsInput(event: ClaudeCodeEvent)
    func claudeCodeUserPrompted(event: ClaudeCodeEvent)
    func claudeCodeStatusChanged(isRunning: Bool)
}

class ClaudeCodeMonitor {
    weak var delegate: ClaudeCodeMonitorDelegate?

    private let eventsDir: String
    private let eventsFile: String
    private var lastFileSize: UInt64 = 0
    private var pollTimer: Timer?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        eventsDir = "\(home)/.claude/focuspal"
        eventsFile = "\(eventsDir)/events.jsonl"
        setup()
    }

    private func setup() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: eventsDir) {
            try? fm.createDirectory(atPath: eventsDir, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: eventsFile) {
            fm.createFile(atPath: eventsFile, contents: nil)
        }

        // Record current file size so we only process new events
        if let attrs = try? FileManager.default.attributesOfItem(atPath: eventsFile),
           let size = attrs[.size] as? UInt64 {
            lastFileSize = size
        }

        // Poll every 0.5 seconds — reliable and lightweight
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForNewEvents()
        }
    }

    private func checkForNewEvents() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: eventsFile),
              let currentSize = attrs[.size] as? UInt64 else { return }

        guard currentSize > lastFileSize else { return }

        // Read only the new bytes
        guard let handle = FileHandle(forReadingAtPath: eventsFile) else { return }
        handle.seek(toFileOffset: lastFileSize)
        let data = handle.readDataToEndOfFile()
        handle.closeFile()
        lastFileSize = currentSize

        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }

        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        let decoder = JSONDecoder()

        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let event = try? decoder.decode(ClaudeCodeEvent.self, from: lineData) else { continue }
            handleEvent(event)
        }
    }

    private func handleEvent(_ event: ClaudeCodeEvent) {
        switch event.event.lowercased() {
        case "stop":
            delegate?.claudeCodeDidComplete(event: event)

        case "notification":
            delegate?.claudeCodeAwaitsInput(event: event)

        case "userpromptsubmit":
            delegate?.claudeCodeUserPrompted(event: event)

        case "start":
            delegate?.claudeCodeStatusChanged(isRunning: true)

        default:
            break
        }
    }

    func isTerminalFocused() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }
        let terminalBundleIds = [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "dev.warp.Warp-Stable",
            "com.microsoft.VSCode",
            "com.todesktop.230313mzl4w4u92",
            "net.kovidgoyal.kitty",
            "co.zeit.hyper",
        ]
        return terminalBundleIds.contains(frontApp.bundleIdentifier ?? "")
    }

    deinit {
        pollTimer?.invalidate()
    }
}

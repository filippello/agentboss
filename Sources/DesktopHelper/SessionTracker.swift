import Foundation

struct SessionInfo: Equatable {
    let pid: Int
    let sessionId: String
    let repoName: String
    let cwd: String
    let startedAt: Date
    var isActive: Bool

    var timeAgo: String {
        let interval = Date().timeIntervalSince(startedAt)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }

    static func == (lhs: SessionInfo, rhs: SessionInfo) -> Bool {
        lhs.pid == rhs.pid && lhs.sessionId == rhs.sessionId
    }
}

protocol SessionTrackerDelegate: AnyObject {
    func sessionsDidUpdate(_ sessions: [SessionInfo])
    func sessionDidEnd(session: SessionInfo)
    func sessionDidStart(session: SessionInfo)
}

/// Watches `~/.claude/sessions/` for active Claude Code processes.
/// Each session file is named after its PID, so we verify liveness with `kill(pid, 0)`.
class SessionTracker {
    weak var delegate: SessionTrackerDelegate?
    private(set) var sessions: [SessionInfo] = []
    private var pollTimer: Timer?
    private let sessionsDir: String

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        sessionsDir = "\(home)/.claude/sessions"
    }

    /// Start polling. Call this after the delegate is set.
    func start() {
        scan()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.scan()
        }
    }

    private func scan() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: sessionsDir) else { return }

        var newSessions: [SessionInfo] = []

        for file in files where file.hasSuffix(".json") {
            let path = (sessionsDir as NSString).appendingPathComponent(file)
            guard let data = fm.contents(atPath: path),
                  let text = String(data: data, encoding: .utf8) else { continue }

            // Some session files contain malformed JSON — fall back to regex parsing.
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

            let pid: Int
            let sessionId: String
            let cwd: String
            let startedAtMs: Int64

            if let j = json,
               let p = j["pid"] as? Int,
               let s = j["sessionId"] as? String,
               let c = j["cwd"] as? String,
               let t = j["startedAt"] as? Int64 {
                pid = p; sessionId = s; cwd = c; startedAtMs = t
            } else {
                guard let p = extractInt(from: text, key: "pid"),
                      let s = extractString(from: text, key: "sessionId"),
                      let c = extractString(from: text, key: "cwd"),
                      let t = extractInt64(from: text, key: "startedAt")
                else { continue }
                pid = p; sessionId = s; cwd = c; startedAtMs = t
            }

            let isAlive = kill(Int32(pid), 0) == 0
            guard isAlive else { continue }

            newSessions.append(SessionInfo(
                pid: pid,
                sessionId: sessionId,
                repoName: (cwd as NSString).lastPathComponent,
                cwd: cwd,
                startedAt: Date(timeIntervalSince1970: Double(startedAtMs) / 1000.0),
                isActive: true
            ))
        }

        newSessions.sort { $0.startedAt > $1.startedAt }

        let oldPids = Set(sessions.map { $0.pid })
        let newPids = Set(newSessions.map { $0.pid })

        for pid in oldPids.subtracting(newPids) {
            if let ended = sessions.first(where: { $0.pid == pid }) {
                delegate?.sessionDidEnd(session: ended)
            }
        }
        for pid in newPids.subtracting(oldPids) {
            if let started = newSessions.first(where: { $0.pid == pid }) {
                delegate?.sessionDidStart(session: started)
            }
        }

        if sessions.map({ $0.pid }) != newSessions.map({ $0.pid }) {
            sessions = newSessions
            delegate?.sessionsDidUpdate(newSessions)
        } else {
            sessions = newSessions
        }
    }

    var activeCount: Int {
        sessions.filter { $0.isActive }.count
    }

    deinit {
        pollTimer?.invalidate()
    }

    // MARK: - Regex helpers for malformed JSON

    private func extractString(from text: String, key: String) -> String? {
        let pattern = "\"\(key)\"\\s*:\\s*\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }

    private func extractInt(from text: String, key: String) -> Int? {
        let pattern = "\"\(key)\"\\s*:\\s*(\\d+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return Int(text[range])
    }

    private func extractInt64(from text: String, key: String) -> Int64? {
        let pattern = "\"\(key)\"\\s*:\\s*(\\d+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return Int64(text[range])
    }
}

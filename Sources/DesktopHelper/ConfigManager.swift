import AppKit

struct SiteConfig: Codable {
    let keywords: [String]
    let message: String
    let thresholdSeconds: Int?
}

struct AppConfig: Codable {
    let bundleIds: [String]
    let message: String
    let thresholdSeconds: Int?
}

struct HealthReminderConfig: Codable {
    let enabled: Bool
    let intervalMinutes: Int
    let onlyWhenWorking: Bool?
    let messages: [String]
}

struct ReminderTimingConfig: Codable {
    let firstDelayMinutes: Int
    let secondDelayMinutes: Int
    let awaitingInputDelayMinutes: Int?
}

struct HelperConfig: Codable {
    let distractionThresholdSeconds: Int
    let characterSize: Int?
    let characterName: String?
    let speechEnabled: Bool?
    let sites: [String: SiteConfig]
    let apps: [String: AppConfig]
    let browserGenericMessage: String
    let defaultMessage: String
    let healthReminder: HealthReminderConfig?
    let reminderTiming: ReminderTimingConfig?
}

/// Loads `config.json` from a few well-known locations, falling back to the
/// bundled default (`Resources/config.default.json`) so the app works out of
/// the box with no manual setup.
class ConfigManager {
    static let shared = ConfigManager()

    private(set) var config: HelperConfig

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        let candidatePaths: [String] = [
            // User-editable location (cwd)
            "\(FileManager.default.currentDirectoryPath)/config.json",
            // User install location
            "\(home)/.desktophelper/config.json",
            // Bundled default
            Bundle.module.url(forResource: "config.default", withExtension: "json")?.path ?? "",
        ].filter { !$0.isEmpty }

        var loaded: HelperConfig?
        for path in candidatePaths {
            if let data = FileManager.default.contents(atPath: path),
               let cfg = try? JSONDecoder().decode(HelperConfig.self, from: data) {
                loaded = cfg
                break
            }
        }

        config = loaded ?? HelperConfig(
            distractionThresholdSeconds: 60,
            characterSize: 96,
            characterName: "Ninja Frog",
            speechEnabled: true,
            sites: [:],
            apps: [:],
            browserGenericMessage: "Your task finished and you haven't come back yet!",
            defaultMessage: "Hey! Your task is done!",
            healthReminder: nil,
            reminderTiming: nil
        )
    }

    /// Find a matching site config from a browser tab title.
    func matchSite(tabTitle: String) -> (name: String, config: SiteConfig)? {
        let lower = tabTitle.lowercased()
        for (name, site) in config.sites {
            for keyword in site.keywords where lower.contains(keyword) {
                return (name, site)
            }
        }
        return nil
    }

    /// Find a matching app config from a bundle ID.
    func matchApp(bundleId: String) -> (name: String, config: AppConfig)? {
        for (name, app) in config.apps where app.bundleIds.contains(bundleId) {
            return (name, app)
        }
        return nil
    }

    /// Threshold in seconds for a given app/site context.
    func threshold(forBundleId bundleId: String, tabTitle: String?) -> TimeInterval {
        if let title = tabTitle, let match = matchSite(tabTitle: title) {
            return TimeInterval(match.config.thresholdSeconds ?? config.distractionThresholdSeconds)
        }
        if let match = matchApp(bundleId: bundleId) {
            return TimeInterval(match.config.thresholdSeconds ?? config.distractionThresholdSeconds)
        }
        return TimeInterval(config.distractionThresholdSeconds)
    }
}

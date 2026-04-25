import Foundation

/// Static collections of rotating messages keyed by feature.
///
/// Each pool returns an `(first, repeat_)` pair: the first variant for the
/// first reminder of the day (or for that session), the second variant when
/// the user has ignored an earlier reminder. Templates may contain
/// `{project}`, `{app}`, `{count}` — fill them via `render(template:)`.
enum MessagePool {

    /// Render a message template with placeholder substitution.
    static func render(_ template: String, project: String, app: String, count: Int) -> String {
        return template
            .replacingOccurrences(of: "{project}", with: project)
            .replacingOccurrences(of: "{app}", with: app)
            .replacingOccurrences(of: "{count}", with: "\(count)")
    }

    /// Reminders fired when Claude Code finished a task and the user hasn't
    /// come back yet. Spicy by design.
    static let taskComplete: [(first: String, repeat_: String)] = [
        (
            "Yo! {project} is done. Get back to work, {app} isn't paying your bills!",
            "Still on {app}? {project} has been waiting for you. Let's go!"
        ),
        (
            "Hey! {project} finished while you were doom scrolling {app}. Time to review!",
            "{project} is gathering dust while you're on {app}. Come on!"
        ),
        (
            "Breaking news: {project} is done! Unlike {app}, it actually needs you.",
            "Plot twist: {project} is STILL done and you're STILL on {app}!"
        ),
        (
            "{project} just dropped. Stop wasting time on {app} and go ship it!",
            "Reminder #{count}: {project} is done. {app} will survive without you."
        ),
        (
            "Your code in {project} is ready! {app} can wait, your deadline can't.",
            "Hey! {project} called, it wants its developer back from {app}."
        ),
        (
            "Task complete in {project}! Close {app} and go be productive!",
            "You've been on {app} long enough. {project} misses you!"
        ),
        (
            "{project} is cooked! Stop scrolling {app} and go check it out!",
            "Earth to developer! {project} is done. {app} is not your job."
        ),
        (
            "Ding! {project} is ready for you. {app}? Not so much. Let's move!",
            "Fun fact: {project} finished ages ago. Less {app}, more coding!"
        ),
        (
            "{project} wrapped up! Your future self will thank you for leaving {app} now.",
            "Still here on {app}? {project} is getting lonely. Go review your code!"
        ),
        (
            "Alert: {project} is done and you're still on {app}. Priorities, friend!",
            "{project} has been done for a while. {app} isn't going anywhere, but your deadline is."
        ),
    ]

    /// Reminders fired when Claude Code is *blocked* waiting for user input.
    /// More urgent in tone than `taskComplete`.
    static let awaitingInput: [(first: String, repeat_: String)] = [
        (
            "Hey! I'm waiting for you to continue in {project}.",
            "Still here! {project} is blocked waiting on you."
        ),
        (
            "{project} needs your input to keep going!",
            "Hello? {project} is still frozen waiting for you."
        ),
        (
            "Yo, {project} is waiting on your approval to move on.",
            "Reminder #{count}: {project} is stuck, needs your go-ahead."
        ),
        (
            "Psst — {project} is paused waiting for you to answer.",
            "Knock knock. {project} is still waiting for your call."
        ),
        (
            "Claude is waiting for you in {project}. Quick review?",
            "{project} has been on hold for a while now. Come unblock it!"
        ),
    ]
}

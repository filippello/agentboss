import AppKit

/// Small persistent floating widget that ticks down a remaining duration.
/// Used by `PomodoroSkill` during the rest phase so the user always sees
/// "how long until I'm back at it". Click to skip the rest early.
class PomodoroCountdownWindow: NSWindow {

    /// Called when the user clicks the widget to skip ahead.
    var onSkip: (() -> Void)?

    /// Called once when the countdown reaches zero.
    var onExpire: (() -> Void)?

    private let label = NSTextField(labelWithString: "")
    private var endsAt: Date?
    private var tickTimer: Timer?
    private var prefix: String = "Rest"

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 56),
            styleMask: .borderless,
            backing: .buffered,
            defer: true
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let container = ClickThroughView(frame: NSRect(x: 0, y: 0, width: 160, height: 56))
        container.wantsLayer = true
        container.onClick = { [weak self] in self?.onSkip?() }

        let bg = NSView(frame: container.bounds)
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.95).cgColor
        bg.layer?.cornerRadius = 12
        container.addSubview(bg)

        label.frame = container.bounds.insetBy(dx: 8, dy: 6)
        label.font = NSFont.monospacedSystemFont(ofSize: 18, weight: .medium)
        label.alignment = .center
        label.textColor = .black
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        container.addSubview(label)

        self.contentView = container
    }

    /// Position the widget near `anchorTopLeft` (top-left corner of the slot
    /// where it should appear) and start counting down to `endsAt`.
    func start(prefix: String, endsAt: Date, anchorTopLeft: NSPoint) {
        self.prefix = prefix
        self.endsAt = endsAt

        // anchorTopLeft → AppKit origin is bottom-left, so subtract our height.
        let origin = NSPoint(
            x: anchorTopLeft.x,
            y: anchorTopLeft.y - frame.height
        )
        setFrameOrigin(origin)
        orderFront(nil)
        updateLabel()

        tickTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    func stop() {
        tickTimer?.invalidate()
        tickTimer = nil
        endsAt = nil
        orderOut(nil)
    }

    private func tick() {
        guard let end = endsAt else { return }
        let remaining = end.timeIntervalSinceNow
        if remaining <= 0 {
            stop()
            onExpire?()
            return
        }
        updateLabel()
    }

    private func updateLabel() {
        guard let end = endsAt else { return }
        let remaining = max(0, end.timeIntervalSinceNow)
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        label.stringValue = String(format: "%@: %02d:%02d", prefix, minutes, seconds)
    }
}

// Catches clicks on any subview region.
private class ClickThroughView: NSView {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

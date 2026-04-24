import AppKit

struct ActionButton {
    let icon: String
    let label: String
    let action: SnoozeOption
}

protocol ActionBubblesDelegate: AnyObject {
    func actionSelected(_ option: SnoozeOption)
}

class ActionBubblesWindow: NSWindow {
    weak var actionDelegate: ActionBubblesDelegate?
    private var buttonWindows: [NSWindow] = []
    private var dismissTimer: Timer?

    private let actions: [ActionButton] = [
        ActionButton(icon: "👍", label: "OK", action: .dismiss),
        ActionButton(icon: "🕐", label: "10 min", action: .tenMinutes),
        ActionButton(icon: "🕐", label: "1 hour", action: .oneHour),
        ActionButton(icon: "🌙", label: "Tomorrow", action: .tomorrow),
    ]

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: .borderless,
            backing: .buffered,
            defer: true
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
    }

    func show(around characterWindow: NSWindow) {
        dismiss()

        let charFrame = characterWindow.frame
        let btnSize = NSSize(width: 62, height: 40)
        let gap: CGFloat = 6

        // 2 buttons on each side of the character
        // Left side: OK, 10 min (from left to right toward character)
        // Right side: 1 hour, Tomorrow (from character to right)
        let positions: [NSPoint] = [
            // Left 2
            NSPoint(x: charFrame.minX - btnSize.width * 2 - gap * 2, y: charFrame.midY - btnSize.height / 2),
            NSPoint(x: charFrame.minX - btnSize.width - gap, y: charFrame.midY - btnSize.height / 2),
            // Right 2
            NSPoint(x: charFrame.maxX + gap, y: charFrame.midY - btnSize.height / 2),
            NSPoint(x: charFrame.maxX + btnSize.width + gap * 2, y: charFrame.midY - btnSize.height / 2),
        ]

        for (index, action) in actions.enumerated() {
            let btnWindow = NSWindow(
                contentRect: NSRect(origin: positions[index], size: btnSize),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            btnWindow.isOpaque = false
            btnWindow.backgroundColor = .clear
            btnWindow.hasShadow = true
            btnWindow.level = .floating
            btnWindow.collectionBehavior = [.canJoinAllSpaces, .stationary]

            let btn = ActionButtonView(
                frame: NSRect(origin: .zero, size: btnSize),
                icon: action.icon,
                label: action.label,
                tag: index
            )
            btn.onClick = { [weak self] tag in
                let option = self?.actions[tag].action ?? .dismiss
                self?.dismiss()
                self?.actionDelegate?.actionSelected(option)
            }
            btnWindow.contentView = btn

            // Animate in
            btnWindow.alphaValue = 0
            btnWindow.orderFront(nil)

            let delay = Double(index) * 0.05
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.2
                    btnWindow.animator().alphaValue = 1
                }
            }

            buttonWindows.append(btnWindow)
        }

        // Auto-dismiss after 15 seconds → default 10 min snooze
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            self?.dismiss()
            self?.actionDelegate?.actionSelected(.tenMinutes)
        }
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        let windows = buttonWindows
        buttonWindows.removeAll()
        // Dismiss async to avoid closing window from within its own click handler
        DispatchQueue.main.async {
            for w in windows {
                w.orderOut(nil)
                w.contentView = nil
            }
        }
    }
}

// MARK: - Individual button view
private class ActionButtonView: NSView {
    var onClick: ((Int) -> Void)?
    private let icon: String
    private let label: String
    private let buttonTag: Int
    private var isHovered = false

    init(frame: NSRect, icon: String, label: String, tag: Int) {
        self.icon = icon
        self.label = label
        self.buttonTag = tag
        super.init(frame: frame)
        wantsLayer = true

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(dirtyRect)

        let rect = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)

        let bgColor = isHovered
            ? NSColor.white
            : NSColor.white.withAlphaComponent(0.9)
        bgColor.setFill()
        path.fill()

        if isHovered {
            NSColor.systemBlue.withAlphaComponent(0.3).setStroke()
            path.lineWidth = 2
            path.stroke()
        }

        // Draw icon + label
        let text = "\(icon)\n\(label)"
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineSpacing = 0

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.black,
            .paragraphStyle: style
        ]
        let textRect = rect.insetBy(dx: 2, dy: 4)
        (text as NSString).draw(in: textRect, withAttributes: attrs)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        onClick?(buttonTag)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

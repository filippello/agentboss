import AppKit

/// Renders a row of `BubbleButton`s flanking the on-screen frog. Buttons are
/// fully data-driven — Skills declare them inside their `walkAndTalk` action
/// and the registry pipes the chosen one back to the originating Skill.
///
/// Layout: up to 4 buttons split 2/2 around the character. Beyond 4, extra
/// buttons stack to the right.
class ActionBubblesWindow: NSWindow {

    // MARK: - Public delegate

    weak var actionDelegate: ActionBubblesDelegate?

    // MARK: - Internal state

    private var buttonWindows: [NSWindow] = []
    private var currentButtons: [BubbleButton] = []
    private var dismissTimer: Timer?

    /// Action to run if the user lets the bubble time out without picking. Set
    /// per-show (so the frog defaults to "snooze 10m" for reminders, but
    /// "cancel" for Pomodoro flow steps).
    private var defaultButtonOnTimeout: BubbleButton?

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

    /// Display `buttons` flanking `characterWindow`. If the user lets the
    /// bubble auto-dismiss, `defaultOnTimeout` (if set) is reported.
    func show(
        buttons: [BubbleButton],
        around characterWindow: NSWindow,
        defaultOnTimeout: BubbleButton? = nil,
        timeoutSeconds: TimeInterval = 15
    ) {
        dismiss()
        currentButtons = buttons
        defaultButtonOnTimeout = defaultOnTimeout

        let charFrame = characterWindow.frame
        let btnSize = NSSize(width: 70, height: 44)
        let gap: CGFloat = 6

        let positions = layoutPositions(buttonCount: buttons.count, charFrame: charFrame, btnSize: btnSize, gap: gap)

        for (index, button) in buttons.enumerated() {
            guard index < positions.count else { break }
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

            let view = ActionButtonView(
                frame: NSRect(origin: .zero, size: btnSize),
                icon: button.icon,
                label: button.label,
                tag: index
            )
            view.onClick = { [weak self] tag in
                guard let self = self, tag < self.currentButtons.count else { return }
                let chosen = self.currentButtons[tag]
                self.dismiss()
                self.actionDelegate?.actionSelected(chosen)
            }
            btnWindow.contentView = view

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

        if let timeoutDefault = defaultOnTimeout {
            dismissTimer = Timer.scheduledTimer(withTimeInterval: timeoutSeconds, repeats: false) { [weak self] _ in
                self?.dismiss()
                self?.actionDelegate?.actionSelected(timeoutDefault)
            }
        }
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        let windows = buttonWindows
        buttonWindows.removeAll()
        currentButtons = []
        DispatchQueue.main.async {
            for w in windows {
                w.orderOut(nil)
                w.contentView = nil
            }
        }
    }

    // MARK: - Layout

    /// Splits up to 4 buttons evenly to the left and right of the character.
    /// 5+ buttons stack to the right. Beyond what the screen can hold we
    /// just clip — Skills should keep their button count to ≤ 4.
    private func layoutPositions(buttonCount: Int, charFrame: NSRect, btnSize: NSSize, gap: CGFloat) -> [NSPoint] {
        let y = charFrame.midY - btnSize.height / 2
        let leftCount = min(buttonCount, 2)
        let rightCount = max(0, buttonCount - leftCount)

        var positions: [NSPoint] = []

        // Left side — leftmost first.
        // Index 0 is the outermost (farthest from character); 1 is closer.
        for i in 0..<leftCount {
            let offset = CGFloat(leftCount - i) * (btnSize.width + gap)
            positions.append(NSPoint(x: charFrame.minX - offset, y: y))
        }
        // Right side — closest first.
        for i in 0..<rightCount {
            let offset = CGFloat(i) * (btnSize.width + gap) + gap
            positions.append(NSPoint(x: charFrame.maxX + offset, y: y))
        }

        return positions
    }
}

// MARK: - Delegate

protocol ActionBubblesDelegate: AnyObject {
    func actionSelected(_ button: BubbleButton)
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

        let bgColor = isHovered ? NSColor.white : NSColor.white.withAlphaComponent(0.9)
        bgColor.setFill()
        path.fill()

        if isHovered {
            NSColor.systemBlue.withAlphaComponent(0.3).setStroke()
            path.lineWidth = 2
            path.stroke()
        }

        let text = "\(icon)\n\(label)"
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineSpacing = 0
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.black,
            .paragraphStyle: style
        ]
        (text as NSString).draw(in: rect.insetBy(dx: 2, dy: 4), withAttributes: attrs)
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent)  { isHovered = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent)    { onClick?(buttonTag) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

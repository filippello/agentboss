import AppKit

class SpeechBubbleWindow: NSWindow {
    private let bubbleView: SpeechBubbleView
    private var dismissTimer: Timer?

    init() {
        bubbleView = SpeechBubbleView(frame: NSRect(x: 0, y: 0, width: 280, height: 80))

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 80),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.level = .floating
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]
        self.contentView = bubbleView
    }

    func show(message: String, above window: NSWindow, duration: TimeInterval = 5.0) {
        // Resize bubble to fit text
        let maxWidth: CGFloat = 300
        let padding: CGFloat = 32
        let font = NSFont.systemFont(ofSize: 13)
        let textSize = (message as NSString).boundingRect(
            with: NSSize(width: maxWidth - padding * 2, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: font]
        ).size

        let bubbleWidth = min(maxWidth, textSize.width + padding * 2 + 10)
        let bubbleHeight = textSize.height + padding + 20  // extra for tail

        let frame = NSRect(
            x: window.frame.midX - bubbleWidth / 2,
            y: window.frame.maxY + 8,
            width: bubbleWidth,
            height: bubbleHeight
        )
        self.setFrame(frame, display: false)
        bubbleView.frame = NSRect(origin: .zero, size: frame.size)
        bubbleView.message = message
        bubbleView.needsDisplay = true

        // Animate in
        self.alphaValue = 0
        self.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            self.animator().alphaValue = 1
        }

        // Auto dismiss
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
        })
    }
}

// MARK: - Bubble Drawing View
private class SpeechBubbleView: NSView {
    var message: String = ""

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(dirtyRect)

        let tailHeight: CGFloat = 10
        let cornerRadius: CGFloat = 12
        let bubbleRect = NSRect(
            x: 4, y: tailHeight + 4,
            width: bounds.width - 8,
            height: bounds.height - tailHeight - 8
        )

        // Bubble body
        let path = NSBezierPath(roundedRect: bubbleRect, xRadius: cornerRadius, yRadius: cornerRadius)

        // Tail (triangle pointing down)
        let tailWidth: CGFloat = 14
        let tailX = bubbleRect.midX
        path.move(to: NSPoint(x: tailX - tailWidth / 2, y: bubbleRect.minY))
        path.line(to: NSPoint(x: tailX, y: bubbleRect.minY - tailHeight))
        path.line(to: NSPoint(x: tailX + tailWidth / 2, y: bubbleRect.minY))
        path.close()

        // Fill and stroke
        NSColor.white.withAlphaComponent(0.95).setFill()
        path.fill()

        NSColor.systemGray.withAlphaComponent(0.3).setStroke()
        path.lineWidth = 1
        path.stroke()

        // Draw text
        let textRect = bubbleRect.insetBy(dx: 14, dy: 8)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraphStyle
        ]

        (message as NSString).draw(in: textRect, withAttributes: attributes)
    }
}

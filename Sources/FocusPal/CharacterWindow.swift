import AppKit

class CharacterWindow: NSWindow {
    // 96x96 to fit the appearing/disappearing sprites, character renders centered
    private let characterSize = NSSize(width: 96, height: 96)

    init() {
        // Position at bottom-right of screen, above the dock
        let screen = NSScreen.main!
        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.maxX - characterSize.width - 20,
            y: visibleFrame.minY + 10
        )
        let frame = NSRect(origin: origin, size: characterSize)

        super.init(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        // Transparent, always-on-top, no shadow
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .floating
        self.ignoresMouseEvents = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]
        self.isMovableByWindowBackground = true

        // Set up the character view
        let characterView = CharacterView(frame: NSRect(origin: .zero, size: characterSize))
        self.contentView = characterView
    }
}

import AppKit

struct SpriteAnimation {
    let sheet: NSImage
    let frameCount: Int
    let frameWidth: CGFloat
    let frameHeight: CGFloat
    let frameDuration: TimeInterval
    let loops: Bool
}

class SpriteAnimator {
    // Character animations (32x32 per frame)
    let idle: SpriteAnimation
    let run: SpriteAnimation
    let jump: SpriteAnimation
    let fall: SpriteAnimation
    let doubleJump: SpriteAnimation
    let hit: SpriteAnimation
    let wallJump: SpriteAnimation

    // Appear/disappear animations (96x96 per frame)
    let appearing: SpriteAnimation
    let disappearing: SpriteAnimation

    init?(characterDir: String, sharedDir: String) {
        guard
            let idleImg = Self.loadImage(characterDir, "Idle (32x32).png"),
            let runImg = Self.loadImage(characterDir, "Run (32x32).png"),
            let jumpImg = Self.loadImage(characterDir, "Jump (32x32).png"),
            let fallImg = Self.loadImage(characterDir, "Fall (32x32).png"),
            let doubleJumpImg = Self.loadImage(characterDir, "Double Jump (32x32).png"),
            let hitImg = Self.loadImage(characterDir, "Hit (32x32).png"),
            let wallJumpImg = Self.loadImage(characterDir, "Wall Jump (32x32).png"),
            let appearImg = Self.loadImage(sharedDir, "Appearing (96x96).png"),
            let disappearImg = Self.loadImage(sharedDir, "Desappearing (96x96).png")
        else {
            return nil
        }

        // Frame size is detected per-sheet from the PNG height (we assume
        // square frames laid out horizontally — true for both Pixel
        // Adventure assets and the petdex slices we generate). This lets
        // bundled chars stay 32x32 while imported pets render at 96x96.
        idle = Self.makeAnimation(sheet: idleImg, duration: 0.08, loops: true)
        run = Self.makeAnimation(sheet: runImg, duration: 0.07, loops: true)
        jump = Self.makeAnimation(sheet: jumpImg, duration: 0.1, loops: false)
        fall = Self.makeAnimation(sheet: fallImg, duration: 0.1, loops: false)
        doubleJump = Self.makeAnimation(sheet: doubleJumpImg, duration: 0.08, loops: false)
        hit = Self.makeAnimation(sheet: hitImg, duration: 0.08, loops: false)
        wallJump = Self.makeAnimation(sheet: wallJumpImg, duration: 0.08, loops: false)
        appearing = Self.makeAnimation(sheet: appearImg, duration: 0.07, loops: false)
        disappearing = Self.makeAnimation(sheet: disappearImg, duration: 0.07, loops: false)
    }

    private static func loadImage(_ dir: String, _ name: String) -> NSImage? {
        let path = (dir as NSString).appendingPathComponent(name)
        return NSImage(contentsOfFile: path)
    }

    private static func makeAnimation(sheet: NSImage, duration: TimeInterval, loops: Bool) -> SpriteAnimation {
        // Square frames laid out horizontally → frame size = sheet height.
        let frameSize = sheet.size.height
        let count = max(1, Int((sheet.size.width / max(frameSize, 1)).rounded()))
        return SpriteAnimation(
            sheet: sheet,
            frameCount: count,
            frameWidth: frameSize,
            frameHeight: frameSize,
            frameDuration: duration,
            loops: loops
        )
    }

    func extractFrame(at index: Int, from animation: SpriteAnimation) -> NSImage {
        let srcX = CGFloat(index) * animation.frameWidth
        // NSImage: origin is bottom-left
        let sourceRect = NSRect(
            x: srcX, y: 0,
            width: animation.frameWidth,
            height: animation.frameHeight
        )

        let frame = NSImage(size: NSSize(width: animation.frameWidth, height: animation.frameHeight))
        frame.lockFocus()
        animation.sheet.draw(
            in: NSRect(x: 0, y: 0, width: animation.frameWidth, height: animation.frameHeight),
            from: sourceRect,
            operation: .copy,
            fraction: 1.0
        )
        frame.unlockFocus()
        return frame
    }
}

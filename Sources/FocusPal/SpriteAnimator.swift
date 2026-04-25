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

        idle = Self.makeAnimation(sheet: idleImg, frameSize: 32, duration: 0.08, loops: true)
        run = Self.makeAnimation(sheet: runImg, frameSize: 32, duration: 0.07, loops: true)
        jump = Self.makeAnimation(sheet: jumpImg, frameSize: 32, duration: 0.1, loops: false)
        fall = Self.makeAnimation(sheet: fallImg, frameSize: 32, duration: 0.1, loops: false)
        doubleJump = Self.makeAnimation(sheet: doubleJumpImg, frameSize: 32, duration: 0.08, loops: false)
        hit = Self.makeAnimation(sheet: hitImg, frameSize: 32, duration: 0.08, loops: false)
        wallJump = Self.makeAnimation(sheet: wallJumpImg, frameSize: 32, duration: 0.08, loops: false)
        appearing = Self.makeAnimation(sheet: appearImg, frameSize: 96, duration: 0.07, loops: false)
        disappearing = Self.makeAnimation(sheet: disappearImg, frameSize: 96, duration: 0.07, loops: false)
    }

    private static func loadImage(_ dir: String, _ name: String) -> NSImage? {
        let path = (dir as NSString).appendingPathComponent(name)
        return NSImage(contentsOfFile: path)
    }

    private static func makeAnimation(sheet: NSImage, frameSize: CGFloat, duration: TimeInterval, loops: Bool) -> SpriteAnimation {
        let count = Int(sheet.size.width / frameSize)
        return SpriteAnimation(
            sheet: sheet,
            frameCount: max(1, count),
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

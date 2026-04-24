import AppKit

enum AnimationType {
    case idle, run, jump, fall, doubleJump, hit, wallJump
    case appearing, disappearing
}

protocol CharacterViewDelegate: AnyObject {
    func characterWasClicked()
}

class CharacterView: NSView {
    weak var clickDelegate: CharacterViewDelegate?
    private var animator: SpriteAnimator?
    private var currentAnimation: SpriteAnimation?
    private var currentType: AnimationType?
    private var currentFrame: Int = 0
    private var animationTimer: Timer?
    private var currentImage: NSImage?
    private var mirrored: Bool = false
    private var onAnimationComplete: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        let character = ConfigManager.shared.config.characterName ?? "Ninja Frog"
        if let baseDir = Self.resolveResourceDir() {
            let charDir = "\(baseDir)/\(character)"
            if let anim = SpriteAnimator(characterDir: charDir, sharedDir: baseDir) {
                self.animator = anim
            }
        }

        playAnimation(.idle)
    }

    /// Locate the bundled "Main Characters" directory. Works both when running via
    /// `swift run` (resources live next to the executable under *.bundle) and when
    /// the app is distributed as a built binary.
    private static func resolveResourceDir() -> String? {
        if let bundled = Bundle.module.resourcePath {
            let candidate = "\(bundled)/Main Characters"
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }
        // Fallback: next to the executable (useful for distribution).
        if let exe = Bundle.main.executableURL?.deletingLastPathComponent() {
            let candidate = exe.appendingPathComponent("Main Characters").path
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(dirtyRect)

        guard let image = currentImage else { return }

        // Scale sprite to fill the view, keeping pixel art crisp
        ctx.interpolationQuality = .none  // nearest-neighbor for pixel art

        if mirrored {
            ctx.saveGState()
            ctx.translateBy(x: bounds.width, y: 0)
            ctx.scaleBy(x: -1, y: 1)
            image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)
            ctx.restoreGState()
        } else {
            image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
    }

    func playAnimation(_ type: AnimationType, mirrored: Bool = false, onComplete: (() -> Void)? = nil) {
        guard let animator = animator else { return }

        self.mirrored = mirrored
        self.onAnimationComplete = onComplete

        // Don't restart if same animation (unless it has a completion handler)
        if type == currentType && onComplete == nil { return }

        let animation: SpriteAnimation
        switch type {
        case .idle:       animation = animator.idle
        case .run:        animation = animator.run
        case .jump:       animation = animator.jump
        case .fall:       animation = animator.fall
        case .doubleJump: animation = animator.doubleJump
        case .hit:        animation = animator.hit
        case .wallJump:   animation = animator.wallJump
        case .appearing:  animation = animator.appearing
        case .disappearing: animation = animator.disappearing
        }

        currentType = type
        currentAnimation = animation
        currentFrame = 0
        updateFrame()
        startAnimationTimer(animation)
    }

    private func startAnimationTimer(_ animation: SpriteAnimation) {
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: animation.frameDuration, repeats: true) { [weak self] _ in
            guard let self = self, let anim = self.currentAnimation else { return }
            self.currentFrame += 1
            if self.currentFrame >= anim.frameCount {
                if anim.loops {
                    self.currentFrame = 0
                } else {
                    self.currentFrame = anim.frameCount - 1
                    self.animationTimer?.invalidate()
                    self.onAnimationComplete?()
                    self.onAnimationComplete = nil
                    return
                }
            }
            self.updateFrame()
        }
    }

    private func updateFrame() {
        guard let animator = animator, let animation = currentAnimation else { return }
        currentImage = animator.extractFrame(at: currentFrame, from: animation)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        clickDelegate?.characterWasClicked()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true  // respond to click even if window isn't focused
    }
}

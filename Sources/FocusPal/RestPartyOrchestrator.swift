import AppKit

/// Spawns a flock of fruits scattered across the screen and three other
/// main characters (Mask Dude, Pink Man, Virtual Guy) that run around
/// "harvesting" them while the user is on a Pomodoro break. When they
/// pick a fruit they play the bundled 6-frame `Collected.png` puff and
/// move on. When `stop()` is called (rest ends or user cancels), every
/// window is torn down.
///
/// Each fruit / harvester is its own borderless transparent NSWindow so
/// the orchestrator never has to share a canvas with the rest of the app.
final class RestPartyOrchestrator {

    private static let fruitNames = [
        "Apple", "Bananas", "Cherries", "Kiwi", "Melon", "Orange", "Pineapple", "Strawberry"
    ]
    private static let harvesterCharacters = ["Mask Dude", "Pink Man", "Virtual Guy"]

    private var fruitWindows: [FruitWindow] = []
    private var harvesterWindows: [HarvesterWindow] = []
    private var stopped = false

    /// Spawn fruits + harvesters for the given rest duration. Number of fruits
    /// is sized so the three harvesters can plausibly clean them all *before*
    /// the rest is over (≈ 60% of the window) — gives the user a satisfying
    /// "they finished cleaning" moment while still leaving the desktop quiet
    /// for the last bit of the break.
    ///
    /// If `restSeconds` is nil, we use a default sensible count (good for the
    /// debug menu's standalone demo).
    func start(restSeconds: TimeInterval? = nil) {
        guard let screen = NSScreen.main else { return }
        let safe = screen.visibleFrame
        stopped = false

        // Math: each harvester takes ~5s per fruit (walk + collect puff).
        // Three harvesters → ~3 fruits/s. We aim to finish at ~60% of rest.
        // For a 5-min (300s) rest that's 180s × 3/5 fruits/s ≈ 100 fruits.
        // For the standalone demo (no rest duration), default to 30.
        let fruitCount: Int
        if let rest = restSeconds {
            let pickupSecondsPerHarvester: Double = 5
            let targetCleanFraction = 0.6
            fruitCount = max(20, Int(Double(Self.harvesterCharacters.count)
                                     * rest * targetCleanFraction
                                     / pickupSecondsPerHarvester))
        } else {
            fruitCount = 30
        }

        // 1) Spawn fruits at random positions inside the visible area, with a
        //    margin so they're not flush against edges.
        let margin: CGFloat = 100
        let xRange = (safe.minX + margin) ... (safe.maxX - margin)
        let yRange = (safe.minY + margin) ... (safe.maxY - margin - 40)  // avoid menu bar
        for _ in 0..<fruitCount {
            let kind = Self.fruitNames.randomElement()!
            let pos = NSPoint(x: CGFloat.random(in: xRange), y: CGFloat.random(in: yRange))
            if let win = FruitWindow(kind: kind, at: pos) {
                win.orderFront(nil)
                fruitWindows.append(win)
            }
        }

        // 2) Spawn one harvester per other character. Start each from a random
        //    edge of the screen so they walk in.
        for character in Self.harvesterCharacters {
            guard let win = HarvesterWindow(character: character) else { continue }
            // Random off-screen start point (left or right side, random Y)
            let startX = Bool.random() ? safe.minX - 80 : safe.maxX + 16
            let startY = CGFloat.random(in: yRange)
            win.setFrameOrigin(NSPoint(x: startX, y: startY))
            win.orderFront(nil)
            harvesterWindows.append(win)
            sendHarvesterToNextFruit(win)
        }
    }

    /// Tear down every spawned window. Idempotent.
    func stop() {
        stopped = true
        for w in fruitWindows { w.close() }
        for w in harvesterWindows { w.close() }
        fruitWindows.removeAll()
        harvesterWindows.removeAll()
    }

    // MARK: - Internal harvester loop

    private func nextUncollectedFruit() -> FruitWindow? {
        return fruitWindows.first { !$0.isCollected }
    }

    private func sendHarvesterToNextFruit(_ harvester: HarvesterWindow) {
        guard !stopped, let fruit = nextUncollectedFruit() else {
            // No fruits left — walk off-screen and stop. Don't tear down here;
            // stop() takes care of cleanup at end of rest.
            walkOffScreen(harvester)
            return
        }

        fruit.isReserved = true
        let target = NSPoint(x: fruit.frame.midX - harvester.frame.width / 2,
                             y: fruit.frame.midY - harvester.frame.height / 2)
        harvester.walkTo(target) { [weak self, weak fruit, weak harvester] in
            guard let self = self,
                  let fruit = fruit,
                  let harvester = harvester,
                  !self.stopped else { return }
            fruit.collect { [weak self, weak harvester] in
                guard let self = self,
                      let harvester = harvester,
                      !self.stopped else { return }
                self.sendHarvesterToNextFruit(harvester)
            }
        }
    }

    private func walkOffScreen(_ harvester: HarvesterWindow) {
        guard let screen = NSScreen.main else { return }
        let safe = screen.visibleFrame
        // Pick whichever edge is closer
        let exitX = (harvester.frame.midX > safe.midX) ? safe.maxX + 80 : safe.minX - 80
        let target = NSPoint(x: exitX, y: harvester.frame.origin.y)
        harvester.walkTo(target) { /* harvester sits off-screen until stop() */ }
    }
}

// MARK: - Fruit window

/// Borderless transparent window containing a single bobbing fruit sprite.
/// `collect()` swaps to the 6-frame `Collected.png` puff and orders out.
private final class FruitWindow: NSWindow {
    var isCollected = false
    var isReserved = false      // claimed by a harvester walking toward it

    private let view: FruitView

    init?(kind: String, at position: NSPoint) {
        let size: CGFloat = 96      // match the main character window size
        guard let v = FruitView(kind: kind, size: size) else { return nil }
        view = v
        super.init(
            contentRect: NSRect(origin: position, size: NSSize(width: size, height: size)),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        // NSWindow defaults to isReleasedWhenClosed = true, which combined with
        // ARC double-frees the window when the orchestrator's array drops it.
        // Crash was reproducible: SIGSEGV inside objc_release during the run-
        // loop autorelease pool pop. Always opt out for ARC-managed windows.
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        contentView = view
    }

    func collect(completion: @escaping () -> Void) {
        guard !isCollected else { completion(); return }
        isCollected = true
        view.playCollected { [weak self] in
            self?.orderOut(nil)
            completion()
        }
    }
}

// MARK: - Fruit view (animated sprite)

private final class FruitView: NSView {
    private let frames: [NSImage]
    private let collectedFrames: [NSImage]
    private var currentFrame = 0
    private var timer: Timer?
    private var playingCollected = false
    private var collectedCompletion: (() -> Void)?

    init?(kind: String, size: CGFloat) {
        guard let resourcePath = Bundle.module.resourcePath else { return nil }
        let fruitsDir = "\(resourcePath)/Items/Fruits"

        guard let frames = Self.loadFrames(path: "\(fruitsDir)/\(kind).png", frameSize: 32),
              let collected = Self.loadFrames(path: "\(fruitsDir)/Collected.png", frameSize: 32)
        else { return nil }

        self.frames = frames
        self.collectedFrames = collected
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true
        startBobbing()
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func loadFrames(path: String, frameSize: CGFloat) -> [NSImage]? {
        guard let sheet = NSImage(contentsOfFile: path) else { return nil }
        let count = Int(sheet.size.width / frameSize)
        guard count > 0 else { return nil }
        var images: [NSImage] = []
        for i in 0..<count {
            let frame = NSImage(size: NSSize(width: frameSize, height: frameSize))
            frame.lockFocus()
            sheet.draw(
                in: NSRect(x: 0, y: 0, width: frameSize, height: frameSize),
                from: NSRect(x: CGFloat(i) * frameSize, y: 0, width: frameSize, height: frameSize),
                operation: .copy,
                fraction: 1.0
            )
            frame.unlockFocus()
            images.append(frame)
        }
        return images
    }

    private func startBobbing() {
        currentFrame = Int.random(in: 0..<frames.count)
        let t = Timer(timeInterval: 0.09, repeats: true) { [weak self] _ in
            self?.tick(loops: true)
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        needsDisplay = true
    }

    func playCollected(completion: @escaping () -> Void) {
        timer?.invalidate()
        playingCollected = true
        collectedCompletion = completion
        currentFrame = 0
        let t = Timer(timeInterval: 0.07, repeats: true) { [weak self] _ in
            self?.tick(loops: false)
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        needsDisplay = true
    }

    private func tick(loops: Bool) {
        currentFrame += 1
        let pool = playingCollected ? collectedFrames : frames
        if currentFrame >= pool.count {
            if loops {
                currentFrame = 0
            } else {
                currentFrame = pool.count - 1
                timer?.invalidate()
                timer = nil
                let cb = collectedCompletion
                collectedCompletion = nil
                cb?()
                return
            }
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(dirtyRect)
        ctx.interpolationQuality = .none

        let pool = playingCollected ? collectedFrames : frames
        guard currentFrame < pool.count else { return }
        let img = pool[currentFrame]
        img.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    deinit { timer?.invalidate() }
}

// MARK: - Harvester window

/// Borderless window with a running character that can be moved to any
/// point on screen. Reuses the same Run sprite as the main frog.
private final class HarvesterWindow: NSWindow {
    private let view: HarvesterView
    private var moveTimer: Timer?
    private let speed: CGFloat = 5.5

    init?(character: String) {
        let size: CGFloat = 96      // match the main character window size
        guard let v = HarvesterView(character: character, size: size) else { return nil }
        view = v
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        // See FruitWindow — opt out of NSWindow's auto-release on close.
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        contentView = view
    }

    /// Linear walk toward `target`. Calls `completion` exactly once when arrived
    /// or when the window is closed.
    func walkTo(_ target: NSPoint, completion: @escaping () -> Void) {
        moveTimer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            var origin = self.frame.origin
            let dx = target.x - origin.x
            let dy = target.y - origin.y
            let dist = sqrt(dx * dx + dy * dy)
            // Mirror the run sprite so the character faces movement direction.
            self.view.facingLeft = dx < 0
            if dist <= self.speed {
                self.setFrameOrigin(target)
                self.moveTimer?.invalidate()
                self.moveTimer = nil
                completion()
                return
            }
            origin.x += self.speed * dx / dist
            origin.y += self.speed * dy / dist
            self.setFrameOrigin(origin)
        }
        RunLoop.main.add(t, forMode: .common)
        moveTimer = t
    }

    override func close() {
        moveTimer?.invalidate()
        moveTimer = nil
        super.close()
    }
}

// MARK: - Harvester view

private final class HarvesterView: NSView {
    private let frames: [NSImage]
    private var currentFrame = 0
    private var timer: Timer?
    var facingLeft = false

    init?(character: String, size: CGFloat) {
        guard let resourcePath = Bundle.module.resourcePath else { return nil }
        let path = "\(resourcePath)/Main Characters/\(character)/Run (32x32).png"
        guard let images = Self.loadRunFrames(path: path) else { return nil }
        frames = images
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true
        startAnimating()
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func loadRunFrames(path: String) -> [NSImage]? {
        guard let sheet = NSImage(contentsOfFile: path) else { return nil }
        let frameSize: CGFloat = 32
        let count = Int(sheet.size.width / frameSize)
        guard count > 0 else { return nil }
        var images: [NSImage] = []
        for i in 0..<count {
            let img = NSImage(size: NSSize(width: frameSize, height: frameSize))
            img.lockFocus()
            sheet.draw(
                in: NSRect(x: 0, y: 0, width: frameSize, height: frameSize),
                from: NSRect(x: CGFloat(i) * frameSize, y: 0, width: frameSize, height: frameSize),
                operation: .copy,
                fraction: 1.0
            )
            img.unlockFocus()
            images.append(img)
        }
        return images
    }

    private func startAnimating() {
        let t = Timer(timeInterval: 0.07, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.currentFrame = (self.currentFrame + 1) % max(1, self.frames.count)
            self.needsDisplay = true
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(dirtyRect)
        ctx.interpolationQuality = .none
        guard currentFrame < frames.count else { return }
        let img = frames[currentFrame]
        if facingLeft {
            ctx.saveGState()
            ctx.translateBy(x: bounds.width, y: 0)
            ctx.scaleBy(x: -1, y: 1)
            img.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)
            ctx.restoreGState()
        } else {
            img.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
    }

    deinit { timer?.invalidate() }
}

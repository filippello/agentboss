import AppKit

protocol ScreenEdgeNavigatorDelegate: AnyObject {
    func navigatorDidReachTarget()
    func navigatorDidReachEdge()
}

class ScreenEdgeNavigator {
    weak var delegate: ScreenEdgeNavigatorDelegate?
    private weak var window: NSWindow?
    private var moveTimer: Timer?
    private let speed: CGFloat = 2.0  // pixels per frame
    private let fps: TimeInterval = 1.0 / 60.0

    init(window: NSWindow) {
        self.window = window
    }

    func startWalking(direction: WalkDirection) {
        stopWalking()

        moveTimer = Timer.scheduledTimer(withTimeInterval: fps, repeats: true) { [weak self] _ in
            guard let self = self, let window = self.window else { return }
            let screen = NSScreen.main!.visibleFrame
            var origin = window.frame.origin

            switch direction {
            case .left:
                origin.x -= self.speed
                if origin.x <= screen.minX {
                    origin.x = screen.minX
                    self.stopWalking()
                    self.delegate?.navigatorDidReachEdge()
                }

            case .right:
                origin.x += self.speed
                if origin.x + window.frame.width >= screen.maxX {
                    origin.x = screen.maxX - window.frame.width
                    self.stopWalking()
                    self.delegate?.navigatorDidReachEdge()
                }

            case .toPoint(let targetX):
                let currentX = origin.x + window.frame.width / 2
                if abs(currentX - targetX) < self.speed * 2 {
                    origin.x = targetX - window.frame.width / 2
                    self.stopWalking()
                    self.delegate?.navigatorDidReachTarget()
                } else if currentX < targetX {
                    origin.x += self.speed
                } else {
                    origin.x -= self.speed
                }
            }

            window.setFrameOrigin(origin)
        }
    }

    func stopWalking() {
        moveTimer?.invalidate()
        moveTimer = nil
    }

    var isMoving: Bool {
        moveTimer != nil
    }
}

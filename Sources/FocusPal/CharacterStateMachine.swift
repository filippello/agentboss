import AppKit

enum CharacterState: Equatable {
    case idle
    case alert
    case walking(direction: WalkDirection)
    case talking(message: String)
    case popAndSay(message: String)   // quick pop: appear → bubble → disappear, no walking
    case hiding
    case sleeping
}

enum WalkDirection: Equatable {
    case left
    case right
    case toPoint(CGFloat)

    static func == (lhs: WalkDirection, rhs: WalkDirection) -> Bool {
        switch (lhs, rhs) {
        case (.left, .left), (.right, .right): return true
        case (.toPoint(let a), .toPoint(let b)): return a == b
        default: return false
        }
    }
}

protocol CharacterStateDelegate: AnyObject {
    func stateDidChange(to state: CharacterState)
    func characterDidFinishTalking()
}

class CharacterStateMachine {
    private(set) var state: CharacterState = .idle
    weak var delegate: CharacterStateDelegate?

    private var pendingMessage: String?
    private var isReturning = false

    func transition(to newState: CharacterState) {
        state = newState
        delegate?.stateDidChange(to: newState)
    }

    func onClaudeCodeEvent(message: String) {
        guard state == .idle || state == .sleeping else { return }
        pendingMessage = message
        isReturning = false
        transition(to: .alert)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self, self.state == .alert else { return }
            let screenCenter = NSScreen.main!.visibleFrame.midX
            self.transition(to: .walking(direction: .toPoint(screenCenter)))
        }
    }

    func onReachedTarget() {
        if isReturning {
            isReturning = false
            // Transition to hiding — the delegate handles the disappearing animation
            // and calls onHideComplete when done
            transition(to: .hiding)
        } else if case .walking(direction: .toPoint) = state {
            transition(to: .talking(message: pendingMessage ?? "Task complete!"))
            pendingMessage = nil
        }
    }

    /// Called by delegate after the disappearing animation is fully done
    func onHideComplete() {
        transition(to: .idle)
    }

    /// Quick pop reminder: appear in place, say a message, disappear.
    /// No walking, no snooze buttons. Delegate handles the full animation chain
    /// and must call onHideComplete() when disappearing is done.
    func popAndSay(message: String) {
        guard state == .idle || state == .sleeping else { return }
        transition(to: .popAndSay(message: message))
    }

    func onFinishedTalking() {
        delegate?.characterDidFinishTalking()
        isReturning = true
        let screen = NSScreen.main!.visibleFrame
        let restX = screen.maxX - 100
        transition(to: .walking(direction: .toPoint(restX)))
    }
}

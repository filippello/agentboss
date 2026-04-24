import AppKit

protocol SpeechControllerDelegate: AnyObject {
    func speechDidFinish()
}

class SpeechController {
    weak var delegate: SpeechControllerDelegate?
    private var bubbleWindow: SpeechBubbleWindow
    private var dismissTimer: Timer?

    init() {
        bubbleWindow = SpeechBubbleWindow()
    }

    func speak(message: String, above characterWindow: NSWindow) {
        let duration = max(3.0, Double(message.count) / 10.0)
        bubbleWindow.show(message: message, above: characterWindow, duration: duration)

        // After bubble duration, notify that speech is done
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.bubbleWindow.dismiss()
            self?.delegate?.speechDidFinish()
        }
    }

    func stop() {
        dismissTimer?.invalidate()
        bubbleWindow.dismiss()
    }
}

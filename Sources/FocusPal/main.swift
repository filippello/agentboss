import AppKit

// Background agent app — no Dock icon. Set activation policy first.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// macOS aggressively auto-terminates "inactive" agent apps under the App Nap
// + Automatic Termination heuristics — which for FocusPal is exactly the wrong
// thing: the menu-bar frog is supposed to live forever waiting for events.
// Tell the system explicitly we want to stay alive. Info.plist has the
// matching `NSSupportsAutomaticTermination`/`NSSupportsSuddenTermination`
// keys set to false; this belt-and-suspenders programmatic call covers cases
// where the plist isn't applied (e.g. unbundled `swift run`).
ProcessInfo.processInfo.disableAutomaticTermination("FocusPal must stay alive in the menu bar")
ProcessInfo.processInfo.disableSuddenTermination()

let delegate = AppDelegate()
app.delegate = delegate
app.run()

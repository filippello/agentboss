import AppKit

// Make this a background agent app (no dock icon)
// We set the activation policy before creating any windows
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate
app.run()

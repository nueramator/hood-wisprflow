import AppKit

// Wispr Flow — a system-wide, hold-to-talk voice dictation tool for macOS.
// Runs as a menu-bar agent (no Dock icon). Entry point.

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu-bar agent, no Dock icon
app.run()

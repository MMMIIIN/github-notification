import AppKit

// Entry point for the menu bar agent. We drive NSApplication manually rather
// than using @main so the executable target stays a plain SwiftPM binary.
// Top-level code runs on the main thread, so assuming main-actor isolation is
// safe and lets us construct the @MainActor AppDelegate.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}

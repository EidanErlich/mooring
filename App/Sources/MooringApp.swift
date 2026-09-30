import AppKit

@main
@MainActor
enum MooringApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate  // weak reference; keep `delegate` alive for the whole run
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

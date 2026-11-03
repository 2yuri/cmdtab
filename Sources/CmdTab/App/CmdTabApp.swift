import AppKit

@main
@MainActor
enum CmdTabApp {
    static func main() {
        if CommandLine.arguments.contains(ClaudeHookClient.argument) {
            ClaudeHookClient.run()
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

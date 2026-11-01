import os

/// Diagnostics. Debug-level messages cost nearly nothing unless someone is streaming them:
/// `log stream --level debug --predicate 'subsystem == "dev.yuri.CmdTab"'`
enum Log {
    static let switcher = Logger(subsystem: "dev.yuri.CmdTab", category: "Switcher")
    static let activation = Logger(subsystem: "dev.yuri.CmdTab", category: "Activation")
}

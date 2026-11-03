import Darwin
import Dispatch

/// Turns the native ⌘⇥ switcher off while CmdTab runs and guarantees it comes back.
///
/// Disabling a symbolic hot key is global WindowServer state that survives the process,
/// so restoring it is wired to every exit path we can intercept: normal termination,
/// `atexit`, the usual termination signals (`kill`, Ctrl-C, logout), and crashes (a crash would
/// otherwise leave ⌘⇥ dead until CmdTab is opened again).
@MainActor
final class NativeSwitcherGuard {
    private var signalSources: [DispatchSourceSignal] = []
    private(set) var isNativeSwitcherDisabled = false

    func disableNativeSwitcher() {
        guard !isNativeSwitcherDisabled else { return }
        Self.setNativeSwitcher(enabled: false)
        isNativeSwitcherDisabled = true
        installExitHandlers()
    }

    func restoreNativeSwitcher() {
        guard isNativeSwitcherDisabled else { return }
        Self.setNativeSwitcher(enabled: true)
        isNativeSwitcherDisabled = false
    }

    nonisolated private static func setNativeSwitcher(enabled: Bool) {
        for hotKey in PrivateAPI.SymbolicHotKey.allCases {
            PrivateAPI.setSymbolicHotKey(hotKey, enabled: enabled)
        }
    }

    private func installExitHandlers() {
        guard signalSources.isEmpty else { return }

        atexit { NativeSwitcherGuard.setNativeSwitcher(enabled: true) }

        for signalNumber in [SIGTERM, SIGINT, SIGHUP, SIGQUIT] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { exit(0) } // `exit` runs the atexit handler above.
            source.resume()
            signalSources.append(source)
        }

        // A crash: give ⌘⇥ back, then let the crash carry on as it would (and leave its report).
        for signalNumber in Self.crashSignals {
            signal(signalNumber) { received in
                signal(received, SIG_DFL)
                NativeSwitcherGuard.setNativeSwitcher(enabled: true)
                raise(received)
            }
        }
    }

    nonisolated static let crashSignals: [Int32] = [SIGTRAP, SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE]
}

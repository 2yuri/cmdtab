import Observation

/// Calls `perform` with the new value every time something read by `value` changes.
/// A lightweight bridge from `@Observable` models to AppKit code.
@MainActor
func observeChanges<Value>(
    of value: @escaping @MainActor () -> Value,
    perform: @escaping @MainActor (Value) -> Void
) {
    withObservationTracking {
        _ = value()
    } onChange: {
        // `onChange` fires before the new value is stored; read it on the next main-actor turn.
        Task { @MainActor in
            perform(value())
            observeChanges(of: value, perform: perform)
        }
    }
}

import AppKit
import SwiftUI

extension View {
    /// Scrolling over the view steps a value: one notch of a mouse wheel, or a short swipe on a
    /// trackpad, is one step (+1 scrolling up, −1 down). Listens only while the pointer is over it.
    func onScrollStep(_ action: @escaping (Int) -> Void) -> some View {
        modifier(ScrollStepModifier(action: action))
    }
}

private struct ScrollStepModifier: ViewModifier {
    let action: (Int) -> Void
    @State private var stepper = ScrollStepper()

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { stepper.start(action) } else { stepper.stop() }
            }
            .onDisappear { stepper.stop() }
    }
}

@MainActor
final class ScrollStepper {
    private var monitor: Any?
    private var accumulated: CGFloat = 0

    /// Trackpad points per step.
    static let swipePerStep: CGFloat = 14

    func start(_ action: @escaping (Int) -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            // Sideways swipes belong to whatever scrolls sideways under the pointer (a carousel).
            if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) { return event }
            let scroll = Scroll(
                delta: event.scrollingDeltaY, isPrecise: event.hasPreciseScrollingDeltas,
                began: event.phase == .began, isMomentum: !event.momentumPhase.isEmpty
            )
            MainActor.assumeIsolated {
                guard let self else { return }
                let steps = self.steps(for: scroll)
                if steps != 0 { action(steps) }
            }
            return nil // The scroll is ours while the pointer is here.
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        accumulated = 0
    }

    private struct Scroll: Sendable {
        var delta: CGFloat
        var isPrecise: Bool
        var began: Bool
        var isMomentum: Bool
    }

    private func steps(for scroll: Scroll) -> Int {
        // The glide after a swipe would keep stepping on its own.
        guard !scroll.isMomentum else { return 0 }
        guard scroll.isPrecise else {
            return scroll.delta > 0 ? 1 : scroll.delta < 0 ? -1 : 0
        }
        if scroll.began { accumulated = 0 }
        accumulated += scroll.delta
        let steps = Int(accumulated / Self.swipePerStep)
        accumulated -= CGFloat(steps) * Self.swipePerStep
        return steps
    }
}

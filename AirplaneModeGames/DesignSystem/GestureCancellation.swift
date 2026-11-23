import SwiftUI

// SwiftUI never calls a drag's `onEnded` when the system cancels it (a notification or Control
// Center pulled down mid-drag, a second finger, the app going inactive). State that only
// `onEnded` resets then stays stuck: a card left a few points off, a selection line left on
// screen. These helpers give every drag a reliable "it's over" signal:
//
//     @GestureState private var dragActive = false
//     DragGesture().tracking($dragActive).onChanged { ... }.onEnded { ... }
//     someView.onGestureCancelled(dragActive) { resetDragState() }
//
// The reset runs one turn of the run loop after the gesture stops, after any `onEnded`, so it
// must be idempotent: a no-op when `onEnded` already cleaned up.

extension Gesture {
    /// Sets `active` to true while the gesture runs; SwiftUI resets it however the gesture stops.
    func tracking(_ active: GestureState<Bool>) -> GestureStateGesture<Self, Bool> {
        updating(active) { _, state, _ in state = true }
    }
}

extension View {
    /// Runs `reset` after a tracked gesture stops, whether it ended or was cancelled.
    func onGestureCancelled(_ active: Bool, perform reset: @escaping @MainActor () -> Void) -> some View {
        onChange(of: active) { _, isActive in
            guard !isActive else { return }
            Task { @MainActor in reset() }
        }
    }
}

import SwiftUI
import UIKit

/// Which of the navigation controller's swipe-to-go-back gestures a game screen turns off.
enum SwipeBackBlock {
    /// Only the swipe-anywhere-in-the-content gesture (iOS 26+), which competes with in-game drags.
    /// The left-edge swipe still goes back.
    case content
    /// Both the content and the edge gesture, for games steered by swiping across the whole screen.
    case all
}

extension View {
    /// Disables swipe-to-go-back while this screen is visible; the back button still works.
    func blocksSwipeBack(_ block: SwipeBackBlock) -> some View {
        background(SwipeBackBlocker(block: block).allowsHitTesting(false).accessibilityHidden(true))
    }
}

private struct SwipeBackBlocker: UIViewControllerRepresentable {
    let block: SwipeBackBlock

    func makeUIViewController(context: Context) -> Controller { Controller(block: block) }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.block = block
        controller.apply()
    }

    final class Controller: UIViewController {
        var block: SwipeBackBlock
        private var isVisible = false

        init(block: SwipeBackBlock) {
            self.block = block
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            isVisible = true
            apply()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            isVisible = false
            apply()
        }

        /// Gestures are re-enabled as soon as the screen starts leaving, so the previous screen
        /// (the home grid) keeps its normal behavior.
        func apply() {
            guard let nav = navigationController else { return }
            nav.interactivePopGestureRecognizer?.isEnabled = !(isVisible && block == .all)
            if #available(iOS 26, *) {
                nav.interactiveContentPopGestureRecognizer?.isEnabled = !isVisible
            }
        }
    }
}

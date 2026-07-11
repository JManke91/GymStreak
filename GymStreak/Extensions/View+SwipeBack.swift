import SwiftUI
import UIKit

/// Restores edge-swipe-to-back on a `NavigationStack` destination that hides
/// the system navigation bar via `.toolbar(.hidden, for: .navigationBar)`.
/// Hiding the bar removes the back-button affordance, which makes
/// `UINavigationController`'s own delegate refuse `interactivePopGestureRecognizer`.
/// This installs a permissive delegate instead.
private struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.isHidden = true
        controller.view.isUserInteractionEnabled = false
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Re-applied on every SwiftUI update pass: UIKit reasserts its own
        // delegate around push/pop transitions, so a one-time assignment
        // isn't reliable.
        DispatchQueue.main.async {
            guard let navigationController = uiViewController.navigationController,
                  let popGesture = navigationController.interactivePopGestureRecognizer else { return }
            context.coordinator.navigationController = navigationController
            popGesture.delegate = context.coordinator
            popGesture.isEnabled = true
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var navigationController: UINavigationController?

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            // Never allow popping the root of the stack.
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }
}

extension View {
    /// Re-enables edge-swipe-to-back when this destination hides the system
    /// navigation bar with `.toolbar(.hidden, for: .navigationBar)`.
    func swipeBackEnabled() -> some View {
        background(SwipeBackEnabler())
    }
}

//
//  MainThreadStallProbe.swift
//  GymStreak
//

#if DEBUG
import SwiftUI

/// UI-test-only measurement of delayed main-run-loop service while exercising a screen.
///
/// A common-mode timer keeps firing during scroll tracking. Any late callback is the exact
/// condition behind "the UI does not react": the main thread could not service its run loop.
///
/// Written for History (docs/history-performance.md §5) and reused unchanged by the Routinen
/// tab, whose rendering defects were the same two rules.
@MainActor
final class MainThreadStallProbe: ObservableObject {
    @Published private(set) var maximumDelayMilliseconds = 0

    private let interval: TimeInterval = 0.02
    private var expectedFireDate = Date()
    private var timer: Timer?

    private var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-UI_TEST_STALL_PROBE")
    }

    init() {}

    func reset() {
        guard isEnabled else { return }
        maximumDelayMilliseconds = 0
        expectedFireDate = Date().addingTimeInterval(interval)

        guard timer == nil else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.recordTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func recordTick() {
        let now = Date()
        let delay = max(0, now.timeIntervalSince(expectedFireDate))
        expectedFireDate = now.addingTimeInterval(interval)
        let milliseconds = Int((delay * 1_000).rounded())
        if milliseconds > maximumDelayMilliseconds {
            maximumDelayMilliseconds = milliseconds
        }
    }
}

/// Isolates probe publications from the screen root: timer updates invalidate only this
/// one-pixel UI-test surface, never the screen whose responsiveness is being measured.
struct MainThreadStallProbeOverlay: View {
    @ObservedObject var probe: MainThreadStallProbe
    /// Accessibility identifier the UI test reads the value from — one per screen.
    let identifier: String

    var body: some View {
        Text("\(probe.maximumDelayMilliseconds)")
            .accessibilityIdentifier(identifier)
            .accessibilityValue("\(probe.maximumDelayMilliseconds)")
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
    }
}
#endif

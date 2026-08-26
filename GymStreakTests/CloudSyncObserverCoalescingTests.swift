//
//  CloudSyncObserverCoalescingTests.swift
//  GymStreakTests
//
//  Pins the coalescing of `.NSPersistentStoreRemoteChange` into
//  `.cloudKitDataDidChange`. Four handlers refetch on every fan-out, so a bulk
//  CloudKit import used to cost hundreds of main-actor SwiftData fetches; the
//  observer now fans out leading-edge first and collapses the rest of a burst
//  into one trailing event per window.
//
//  **Shape rule for anything added here.** `syncVersion` counts fan-outs
//  exactly, so assert on counts — but every assertion must be made *after*
//  enough real time has passed for the opposite behaviour to have shown itself.
//  A count checked too early passes against a coalescer that never fires at all,
//  which is the failure this file exists to catch. Hence the short injected
//  window and the explicit sleeps in window multiples.
//
//  **Both notifications here are process-wide**, so a concurrently running test
//  would count this suite's posts and vice versa — `ExerciseCatalogSenderTests`
//  posts `.cloudKitDataDidChange` too. Two things keep that apart, and the
//  second is the load-bearing one: `.serialized` orders the tests *within* this
//  suite, and `GymStreak.xctestplan` declares `GymStreakTests`
//  `"parallelizable": false`, which is what stops other suites from overlapping.
//  If that flag is ever flipped, this suite is where it will surface.
//

import Testing
import CoreData
import Foundation
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct CloudSyncObserverCoalescingTests {

    /// Short enough to keep the suite fast, long enough that the main-actor
    /// hops in between are noise by comparison.
    private static let window = Duration.milliseconds(100)

    private func makeObserver() -> CloudSyncObserver {
        CloudSyncObserver(coalescingWindow: Self.window)
    }

    private func postRemoteChange(_ count: Int = 1) {
        for _ in 0..<count {
            NotificationCenter.default.post(name: .NSPersistentStoreRemoteChange, object: nil)
        }
    }

    /// Steady-state sync must not feel laggy: the first change of a quiet
    /// period is fanned out without waiting for the window. Asserted a quarter
    /// of a window in, so a purely trailing debounce would still read 0 here.
    @Test
    func isolatedRemoteChangeFansOutWithoutWaitingForTheWindow() async throws {
        let observer = makeObserver()

        postRemoteChange()
        try await Task.sleep(for: Self.window / 4)

        #expect(observer.syncVersion == 1)
    }

    /// The burst case. Twenty notifications land inside one window and cost two
    /// fan-outs — the leading one plus a single trailing one — not twenty.
    @Test
    func burstOfRemoteChangesCollapsesToLeadingAndTrailingFanOut() async throws {
        let observer = makeObserver()

        postRemoteChange(20)
        // Three windows: one for the trailing fan-out, and two more in which an
        // un-coalesced observer would have emitted the other eighteen.
        try await Task.sleep(for: Self.window * 3)

        #expect(observer.syncVersion == 2)
    }

    /// The window closes when the burst stops, so the next isolated change is
    /// immediate again rather than being held for a still-open window.
    @Test
    func changeAfterTheWindowClosesFansOutImmediatelyAgain() async throws {
        let observer = makeObserver()

        postRemoteChange(5)
        try await Task.sleep(for: Self.window * 3)
        #expect(observer.syncVersion == 2)

        postRemoteChange()
        try await Task.sleep(for: Self.window / 4)

        #expect(observer.syncVersion == 3)
    }

    /// A directly posted `.cloudKitDataDidChange` — the stranded-library
    /// recovery in `DefaultContentSeeder` does exactly this — bypasses the
    /// coalescer entirely and still reaches its consumers at once. Both posts
    /// land inside a single window, so a coalescer sitting on this path would
    /// show one delivery here instead of two.
    @Test
    func directCloudKitDataDidChangePostIsNotCoalesced() async throws {
        let observer = makeObserver()
        let recorder = FanOutRecorder()

        NotificationCenter.default.post(name: .cloudKitDataDidChange, object: nil)
        NotificationCenter.default.post(name: .cloudKitDataDidChange, object: nil)
        try await Task.sleep(for: Self.window / 4)

        #expect(recorder.count == 2)
        // Nothing went through the remote-change path, so nothing was throttled.
        #expect(observer.syncVersion == 0)
    }
}

/// Counts `.cloudKitDataDidChange` deliveries. Shaped exactly like the four
/// real consumers — `queue: .main` plus a `Task { @MainActor in }` hop — so
/// what it counts is what they would have refetched on.
@MainActor
private final class FanOutRecorder {
    private(set) var count = 0
    private var token: NSObjectProtocol?

    init() {
        token = NotificationCenter.default.addObserver(
            forName: .cloudKitDataDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.count += 1
            }
        }
    }

    isolated deinit {
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

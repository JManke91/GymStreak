import Testing
@testable import GymStreak

@Suite
@MainActor
struct WatchConnectivityDelegateWorkTrackerTests {
    @Test
    func waitUntilIdleWaitsForRegisteredDelegateWork() async {
        let tracker = WatchConnectivityDelegateWorkTracker()
        tracker.beginWork()
        var didFinishWaiting = false

        let waiter = Task { @MainActor in
            await tracker.waitUntilIdle()
            didFinishWaiting = true
        }

        await Task.yield()
        #expect(!didFinishWaiting)

        tracker.endWork()
        await waiter.value
        #expect(didFinishWaiting)
    }

    @Test
    func waitUntilIdleReturnsImmediatelyWhenNoWorkIsRegistered() async {
        let tracker = WatchConnectivityDelegateWorkTracker()

        await tracker.waitUntilIdle()

        #expect(tracker.isIdle)
    }
}

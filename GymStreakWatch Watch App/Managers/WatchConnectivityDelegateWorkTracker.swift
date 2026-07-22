import Foundation

/// Tracks delegate work before it hops to the main actor, allowing a
/// WatchConnectivity background task to wait for application persistence and
/// queue reconciliation rather than treating callback dispatch as completion.
nonisolated final class WatchConnectivityDelegateWorkTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingWorkCount = 0
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    var isIdle: Bool {
        lock.lock()
        defer { lock.unlock() }
        return pendingWorkCount == 0
    }

    func beginWork() {
        lock.lock()
        pendingWorkCount += 1
        lock.unlock()
    }

    func endWork() {
        lock.lock()
        precondition(pendingWorkCount > 0, "Unbalanced WatchConnectivity delegate work")
        pendingWorkCount -= 1
        let waiters = pendingWorkCount == 0 ? idleWaiters : []
        if pendingWorkCount == 0 {
            idleWaiters.removeAll()
        }
        lock.unlock()

        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitUntilIdle() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if pendingWorkCount == 0 {
                lock.unlock()
                continuation.resume()
            } else {
                idleWaiters.append(continuation)
                lock.unlock()
            }
        }
    }
}

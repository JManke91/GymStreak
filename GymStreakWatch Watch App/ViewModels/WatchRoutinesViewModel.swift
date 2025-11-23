import Foundation
import Combine

@MainActor
final class WatchRoutinesViewModel: ObservableObject {
    @Published var routines: [WatchRoutine] = []
    @Published var isLoading = false
    @Published var lastSyncDate: Date?

    private let routineStore: RoutineStore

    init(routineStore: RoutineStore) {
        self.routineStore = routineStore
        observeStore()
    }

    private func observeStore() {
        // Bind to store's published properties
        routines = routineStore.routines
        isLoading = routineStore.isLoading
        lastSyncDate = routineStore.lastSyncDate
    }

    func refresh() {
        routines = routineStore.routines
        isLoading = routineStore.isLoading
        lastSyncDate = routineStore.lastSyncDate
    }

    var hasRoutines: Bool {
        !routines.isEmpty
    }

    var lastSyncText: String? {
        guard let date = lastSyncDate else { return nil }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Synced \(formatter.localizedString(for: date, relativeTo: Date()))"
    }
}

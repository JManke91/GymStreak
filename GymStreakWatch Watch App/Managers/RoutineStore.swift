import Foundation
import Combine

@MainActor
final class RoutineStore: ObservableObject {
    @Published var routines: [WatchRoutine] = []
    @Published var isLoading = false
    @Published var lastSyncDate: Date?

    private let userDefaults: UserDefaults?
    private let routinesKey = "syncedRoutines"
    private let lastSyncKey = "lastSyncDate"

    init() {
        // Use App Group for shared storage
        self.userDefaults = UserDefaults(suiteName: "group.com.gymstreak.shared")
        loadRoutines()
    }

    // MARK: - Public Methods

    func updateRoutines(_ newRoutines: [WatchRoutine]) {
        routines = newRoutines
        lastSyncDate = Date()
        saveRoutines()
    }

    func routine(for id: UUID) -> WatchRoutine? {
        routines.first { $0.id == id }
    }

    // MARK: - Persistence

    private func loadRoutines() {
        isLoading = true
        defer { isLoading = false }

        guard let userDefaults = userDefaults else {
            print("RoutineStore: UserDefaults not available")
            return
        }

        if let data = userDefaults.data(forKey: routinesKey) {
            do {
                routines = try JSONDecoder().decode([WatchRoutine].self, from: data)
                print("RoutineStore: Loaded \(routines.count) routines")
            } catch {
                print("RoutineStore: Failed to decode routines - \(error.localizedDescription)")
            }
        }

        if let syncDate = userDefaults.object(forKey: lastSyncKey) as? Date {
            lastSyncDate = syncDate
        }
    }

    private func saveRoutines() {
        guard let userDefaults = userDefaults else {
            print("RoutineStore: UserDefaults not available")
            return
        }

        do {
            let data = try JSONEncoder().encode(routines)
            userDefaults.set(data, forKey: routinesKey)
            userDefaults.set(lastSyncDate, forKey: lastSyncKey)
            print("RoutineStore: Saved \(routines.count) routines")
        } catch {
            print("RoutineStore: Failed to encode routines - \(error.localizedDescription)")
        }
    }
}

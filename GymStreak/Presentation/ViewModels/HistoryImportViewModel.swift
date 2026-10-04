//
//  HistoryImportViewModel.swift
//  GymStreak
//
//  Drives the pick → preview → import → summary flow (docs/history-import.md §5).
//

import Foundation
import Observation

@Observable
@MainActor
final class HistoryImportViewModel {

    enum Phase {
        case intro
        case reading
        case preview(HistoryImportPreview)
        case importing(progress: Double)
        case finished(HistoryImportResult)
        case failed(HistoryImportError)
    }

    private(set) var phase: Phase = .intro
    /// The unit the file's weights are in. Strong does not always say, so the user picks;
    /// it starts at their display preference, or at the unit the header names.
    var weightUnit: WeightUnit

    private let importer: any HistoryImporting
    private let catalogSync: ExerciseCatalogSyncRequesting

    init(
        importer: any HistoryImporting,
        catalogSync: ExerciseCatalogSyncRequesting,
        weightUnitPreference: WeightUnitPreferenceProviding
    ) {
        self.importer = importer
        self.catalogSync = catalogSync
        self.weightUnit = weightUnitPreference.weightUnit
    }

    var isBusy: Bool {
        switch phase {
        case .reading, .importing: true
        default: false
        }
    }

    func fileSelected(_ result: Result<URL, any Error>) async {
        guard case .success(let url) = result else {
            // A dismissed or failed picker leaves the user where they were.
            return
        }
        phase = .reading
        do {
            let preview = try await importer.prepareStrongImport(from: url)
            if let detected = preview.file.detectedWeightUnit { weightUnit = detected }
            phase = .preview(preview)
        } catch let error as HistoryImportError {
            phase = .failed(error)
        } catch {
            phase = .failed(.unreadableFile)
        }
    }

    func startImport() async {
        guard case .preview(let preview) = phase else { return }
        phase = .importing(progress: 0)
        do {
            let result = try await importer.importHistory(
                preview.file,
                weightUnit: weightUnit
            ) { [weak self] fraction in
                Task { @MainActor in
                    guard let self, case .importing = self.phase else { return }
                    self.phase = .importing(progress: fraction)
                }
            }
            phase = .finished(result)
            if result.createdExerciseCount > 0 { catalogSync.requestCatalogSync() }
            if result.importedWorkoutCount > 0 || result.createdExerciseCount > 0 {
                NotificationCenter.default.post(name: .workoutHistoryDidChange, object: nil)
                NotificationCenter.default.post(name: .historySourceDataDidChange, object: nil)
            }
        } catch {
            // Saved chunks stay; the import is idempotent, so retrying finishes the rest.
            phase = .failed(error as? HistoryImportError ?? .writeFailed)
        }
    }

    func reset() {
        phase = .intro
    }
}

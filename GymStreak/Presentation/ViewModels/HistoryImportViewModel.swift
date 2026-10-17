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
    /// The app the file must come from — fixed by the entry point.
    let source: HistoryImportSource
    /// The unit the file's weights are in. Strong does not always say, so the user picks;
    /// it starts at their display preference, or at the unit the header names. Hevy's
    /// header always names it, and the picker is hidden (`isWeightUnitCertain`).
    var weightUnit: WeightUnit
    /// Whether unmatched exercise names join the library. Off keeps the library untouched:
    /// those workouts still show in History, and reach the charts once an exercise of the
    /// same name exists.
    var createsMissingExercises = true

    /// First and last selected **day** of the period filter (whole days, inclusive).
    /// Set to the file's full span when a preview arrives.
    var rangeStart = Date() { didSet { if !isApplyingPeriod { refreshSelection() } } }
    var rangeEnd = Date() { didSet { if !isApplyingPeriod { refreshSelection() } } }
    /// Set while `apply(_:)` writes both ends, so the summary is computed once, not twice.
    private var isApplyingPeriod = false
    /// The preview's counts for the selected period — recomputed when the period changes,
    /// never in a view body. The library lookups behind it were made once, off-main.
    private(set) var selection: HistoryImportSelectionSummary?

    private let calendar = Calendar.current
    private let importer: any HistoryImporting
    private let catalogSync: ExerciseCatalogSyncRequesting

    init(
        source: HistoryImportSource,
        importer: any HistoryImporting,
        catalogSync: ExerciseCatalogSyncRequesting,
        weightUnitPreference: WeightUnitPreferenceProviding
    ) {
        self.source = source
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
            let preview = try await importer.prepareImport(from: url, source: source)
            if let detected = preview.file.detectedWeightUnit { weightUnit = detected }
            phase = .preview(preview)
            apply(.everything)
        } catch let error as HistoryImportError {
            phase = .failed(error)
        } catch {
            phase = .failed(.unreadableFile)
        }
    }

    /// Hevy's header names the unit; only an uncertain file asks the user.
    var isWeightUnitCertain: Bool {
        guard case .preview(let preview) = phase else { return false }
        return preview.file.isWeightUnitCertain
    }

    // MARK: - Period

    /// The file's first and last workout day — the date pickers' bounds.
    var selectableDays: ClosedRange<Date>? {
        guard case .preview(let preview) = phase else { return nil }
        return calendar.startOfDay(for: preview.earliest)...preview.latest
    }

    /// The From picker's bounds: the first workout day up to the current To, clamped into the
    /// file's span. Built here rather than in the view because a `ClosedRange` with inverted
    /// bounds traps — the view must never assemble one from freely settable state.
    var fromBounds: ClosedRange<Date>? {
        guard let days = selectableDays else { return nil }
        return days.lowerBound...min(max(rangeEnd, days.lowerBound), days.upperBound)
    }

    /// The To picker's bounds: the current From up to the last workout, clamped likewise.
    var toBounds: ClosedRange<Date>? {
        guard let days = selectableDays else { return nil }
        return max(min(rangeStart, days.upperBound), days.lowerBound)...days.upperBound
    }

    /// Exact instants covered by the selected days.
    var selectedRange: ClosedRange<Date> {
        let start = calendar.startOfDay(for: min(rangeStart, rangeEnd))
        let lastDay = calendar.startOfDay(for: max(rangeStart, rangeEnd))
        let end = calendar.date(byAdding: .day, value: 1, to: lastDay)?.addingTimeInterval(-0.001) ?? lastDay
        return start...end
    }

    /// The preset the current selection equals, if any — for the menu's checkmark.
    var activePeriod: HistoryImportPeriod? {
        guard case .preview(let preview) = phase else { return nil }
        return HistoryImportPeriod.allCases.first { period in
            let days = period.dayRange(earliest: preview.earliest, latest: preview.latest, calendar: calendar)
            return calendar.isDate(days.start, inSameDayAs: rangeStart)
                && calendar.isDate(days.end, inSameDayAs: rangeEnd)
        }
    }

    func apply(_ period: HistoryImportPeriod) {
        guard case .preview(let preview) = phase else { return }
        let days = period.dayRange(earliest: preview.earliest, latest: preview.latest, calendar: calendar)
        isApplyingPeriod = true
        rangeStart = days.start
        rangeEnd = days.end
        isApplyingPeriod = false
        refreshSelection()
    }

    private func refreshSelection() {
        guard case .preview(let preview) = phase else { return }
        let updated = preview.summary(in: selectedRange)
        if updated != selection { selection = updated }
    }

    // MARK: - Import

    func startImport() async {
        guard case .preview(let preview) = phase, (selection?.importableWorkoutCount ?? 0) > 0 else { return }
        let file = preview.file.restricted(to: selectedRange)
        phase = .importing(progress: 0)
        do {
            let result = try await importer.importHistory(
                file,
                weightUnit: weightUnit,
                createsMissingExercises: createsMissingExercises
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
        selection = nil
    }
}

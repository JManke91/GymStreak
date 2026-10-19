//
//  ConditioningShareViewModel.swift
//  GymStreak
//
//  Sharing a recorded conditioning session as an image: the card's data, the preview
//  sheet's layer toggles and the render. See docs/workout-sharing.md.
//

import Observation
import SwiftUI

@Observable
@MainActor
final class ConditioningShareViewModel: ShareCardPreviewing, Identifiable {

    /// Nil until a record is prepared.
    private(set) var card: ConditioningShareCardModel?

    var layers = ConditioningShareLayers() {
        didSet {
            rebuildCard()
            cardDidChange()
        }
    }

    var saveState = ShareSaveState.idle
    var saveError: PhotoSaveError?
    let shareMessage: String

    @ObservationIgnored let photoLibrary: PhotoLibrarySaving
    @ObservationIgnored private let records: any ConditioningRecordRepository
    @ObservationIgnored private let heartRates: any ConditioningHeartRateReading
    @ObservationIgnored private let heartRateProfiles: any HeartRateProfileStoring
    @ObservationIgnored private var source: ConditioningShareSource?

    init(
        records: any ConditioningRecordRepository,
        heartRates: any ConditioningHeartRateReading,
        heartRateProfiles: any HeartRateProfileStoring,
        photoLibrary: PhotoLibrarySaving,
        campaign: String
    ) {
        self.records = records
        self.heartRates = heartRates
        self.heartRateProfiles = heartRateProfiles
        self.photoLibrary = photoLibrary
        self.shareMessage = Self.shareMessage(campaign: campaign)
    }

    /// Reads the record once, then its heart rate from Apple Health.
    ///
    /// The record stores no heart rate. Only a session that reached Apple Health
    /// (`healthKitWorkoutId`) is looked up: with Health sync off the user opted out of
    /// Health, and the card uses its no-heart-rate state.
    ///
    /// - Returns: false when there is no such record.
    @discardableResult
    func prepare(recordID: UUID) async -> Bool {
        guard let record = records.find(id: recordID) else { return false }
        // Projected to values now: the record may be deleted while Health is read.
        let source = ConditioningShareSource(
            title: ConditioningCopy.recordedTitle(sessionType: record.sessionType, snapshot: record.titleSnapshot),
            date: record.startTime,
            duration: record.duration,
            modality: record.modality,
            effort: record.effort,
            roundsCompleted: record.roundsCompleted,
            roundsPlanned: record.roundsPlanned,
            workInterval: record.workInterval,
            restInterval: record.restInterval
        )
        let isInHealth = record.healthKitWorkoutId != nil
        let window = (start: record.startTime, end: record.endTime)
        self.source = source

        if isInHealth {
            let readings = await heartRates.readings(from: window.start, to: window.end)
            self.source?.heartRate = ConditioningHeartRateSummarizer.summarize(
                readings,
                from: window.start,
                to: window.end,
                zoneFloors: HeartRateZones.sessionZoneFloors(for: heartRateProfiles.heartRateProfile)
            )
        }
        rebuildCard()
        return true
    }

    func renderImage() -> UIImage? {
        guard let card else { return nil }
        let renderer = ImageRenderer(
            content: ConditioningShareCardView(model: card).environment(\.colorScheme, .dark)
        )
        renderer.scale = 1
        renderer.isOpaque = true
        return renderer.uiImage
    }

    private func rebuildCard() {
        guard let source else { return }
        card = ConditioningShareCardModel.make(from: source, layers: layers)
    }
}

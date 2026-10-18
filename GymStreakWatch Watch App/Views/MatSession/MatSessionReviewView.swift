//
//  MatSessionReviewView.swift
//  GymStreakWatch Watch App
//
//  After a mat session on the watch (positioning ticket 05,
//  docs/fight-conditioning.md): duration, average and maximum heart rate, and
//  the intensity — preset to the zone-time suggestion when there is one, one
//  tap to change — confirmed before anything is saved. After the round timer
//  (positioning ticket 07) the user can also not save it at all.
//

import SwiftUI

struct MatSessionReviewView: View {
    @Environment(WatchMatSessionViewModel.self) private var mat
    let review: WatchMatSessionViewModel.Review
    let sport: WatchMatSport

    var body: some View {
        ScrollView {
            VStack(spacing: OnyxWatch.Spacing.md) {
                VStack(spacing: 2) {
                    if mat.isRoundTimer {
                        Text("Round timer")
                            .font(.watchCaption)
                            .foregroundStyle(OnyxWatch.Colors.textSecondary)
                    }
                    Text(WatchMatSessionCopy.sport(sport))
                        .font(.watchHeader)
                    if let rounds = review.rounds {
                        Text("\(rounds) rounds · \(WatchConditioningCopy.clock(review.duration))")
                            .font(.watchSubheadline)
                    } else {
                        Text(WatchConditioningCopy.clock(review.duration))
                            .font(.watchNumberLarge)
                    }
                    if let average = review.averageHeartRate, let maximum = review.maximumHeartRate {
                        Text("Avg \(average) · max \(maximum) bpm")
                            .font(.watchCaption)
                            .foregroundStyle(OnyxWatch.Colors.textSecondary)
                    }
                }

                VStack(spacing: OnyxWatch.Spacing.sm) {
                    Text(review.suggested == nil ? "How hard was it?" : "Suggested from your heart-rate zones")
                        .font(.watchCaption)
                        .foregroundStyle(OnyxWatch.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                    ForEach(WatchMatIntensity.allCases) { intensity in
                        intensityButton(intensity)
                    }
                }

                Button(mat.isRoundTimer ? LocalizedStringKey("Save as mat session") : "Save") { Task { await mat.save() } }
                    .disabled(mat.selectedIntensity == nil)
                if mat.isRoundTimer {
                    Button("Don't save", role: .destructive) { mat.discard() }
                        .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, OnyxWatch.Spacing.md)
        }
    }

    private func intensityButton(_ intensity: WatchMatIntensity) -> some View {
        let isSelected = mat.selectedIntensity == intensity
        return Button {
            mat.selectedIntensity = intensity
        } label: {
            Text(WatchMatSessionCopy.intensity(intensity))
                .font(.watchSubheadline)
                // Black on the tint, never white (contrast rule).
                .foregroundStyle(isSelected ? OnyxWatch.Colors.textOnTint : OnyxWatch.Colors.textPrimary)
                .frame(maxWidth: .infinity)
        }
        .tint(isSelected ? OnyxWatch.Colors.tint : OnyxWatch.Colors.cardElevated)
        .buttonStyle(.borderedProminent)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

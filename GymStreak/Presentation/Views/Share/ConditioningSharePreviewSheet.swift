//
//  ConditioningSharePreviewSheet.swift
//  GymStreak
//
//  The share preview for a conditioning session: the shared sheet with the
//  conditioning card and its chips (Rounds, Heart rate, Stats). See docs/workout-sharing.md.
//

import SwiftUI

struct ConditioningSharePreviewSheet: View {

    @Bindable var viewModel: ConditioningShareViewModel

    var body: some View {
        SharePreviewSheet(viewModel: viewModel, title: "share.preview.title_conditioning") {
            if let card = viewModel.card {
                ShareCardScaled(width: 270) { ConditioningShareCardView(model: card) }
            }
        } chips: {
            ShareLayerChip("share.layer.rounds", isOn: $viewModel.layers.rounds)
            // The design hides the chip for a session without heart-rate data.
            if viewModel.card?.isHeartRateChipShown == true {
                ShareLayerChip("share.layer.heart_rate", isOn: $viewModel.layers.heartRate)
            }
            ShareLayerChip("share.layer.stats", isOn: $viewModel.layers.stats)
        }
    }
}

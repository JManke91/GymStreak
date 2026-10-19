//
//  WorkoutSharePreviewSheet.swift
//  GymStreak
//
//  What the user sees between tapping Share and the system share sheet: the live card, the
//  layer chips and the Save and Share buttons. Design: `SharePreview.dc.html`
//  (docs/workout-sharing.md). `SharePreviewSheet` is the shell both cards share; the
//  strength and conditioning sheets only supply the card and its chips.
//

import SwiftUI
import UIKit

struct WorkoutSharePreviewSheet: View {

    @Bindable var viewModel: WorkoutShareViewModel

    var body: some View {
        SharePreviewSheet(viewModel: viewModel) {
            if let card = viewModel.card {
                WorkoutShareCardThumbnail(model: card, width: 270)
            }
        } chips: {
            ShareLayerChip("share.layer.muscles", isOn: $viewModel.layers.muscles)
            if viewModel.card?.isRecordsChipShown == true {
                ShareLayerChip("share.layer.prs", isOn: $viewModel.layers.records)
            }
            ShareLayerChip("share.layer.stats", isOn: $viewModel.layers.stats)
            ShareLayerChip("share.layer.exercises", isOn: $viewModel.layers.exercises)
            ShareLayerChip(
                "share.layer.weights",
                isOn: $viewModel.layers.weights,
                isEnabled: viewModel.card?.isWeightsChipEnabled ?? true
            )
        }
    }
}

struct SharePreviewSheet<Model: ShareCardPreviewing, Card: View, Chips: View>: View {

    let viewModel: Model
    var title = "share.preview.title"
    @ViewBuilder let card: Card
    @ViewBuilder let chips: Chips

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var sharePayload: SharePayload?

    var body: some View {
        VStack(spacing: 12) {
            header
            card
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                }
            FlowLayout(spacing: 8) {
                chips
            }
            .padding(.top, 2)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                saveButton
                shareButton
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 8)
        .background(DesignSystem.Colors.card)
        .presentationDragIndicator(.visible)
        .presentationBackground(DesignSystem.Colors.card)
        .alert(
            saveErrorTitle,
            isPresented: Binding(
                get: { viewModel.saveError != nil },
                set: { if !$0 { viewModel.saveError = nil } }
            ),
            presenting: viewModel.saveError
        ) { error in
            if error == .denied {
                Button("share.save.open_settings".localized) {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                }
                Button("action.cancel".localized, role: .cancel) {}
            } else {
                Button("common.ok".localized, role: .cancel) {}
            }
        } message: { error in
            Text(Self.saveErrorMessage(error))
        }
        .sheet(item: $sharePayload) { payload in
            ActivityShareSheet(items: [payload.image, payload.message])
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
    }

    private var header: some View {
        ZStack {
            Text(title.localized)
                .font(.headline)
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(DesignSystem.Colors.cardElevated, in: Circle())
                        .overlay { Circle().stroke(Color.white.opacity(0.08), lineWidth: 1) }
                }
                .accessibilityLabel("action.close".localized)
                Spacer()
            }
        }
    }

    private var shareButton: some View {
        Button {
            guard let image = viewModel.renderImage() else { return }
            HapticManager.shared.light()
            sharePayload = SharePayload(image: image, message: viewModel.shareMessage)
        } label: {
            Label("share.action".localized, systemImage: "square.and.arrow.up")
                .font(.headline)
                .foregroundStyle(DesignSystem.Colors.textOnTint)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(DesignSystem.Colors.tint, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Straight to Photos, for posting a story from another app without the share sheet.
    private var saveButton: some View {
        let isSaved = viewModel.saveState == .saved
        return Button {
            HapticManager.shared.light()
            Task {
                await viewModel.saveImage()
                if viewModel.saveState == .saved { HapticManager.shared.success() }
            }
        } label: {
            Label(
                (isSaved ? "share.saved" : "share.save").localized,
                systemImage: isSaved ? "checkmark" : "arrow.down.to.line"
            )
            .font(.headline)
            .foregroundStyle(isSaved ? DesignSystem.Colors.tint : .white)
            .padding(.horizontal, 20)
            .frame(height: 52)
            .background(DesignSystem.Colors.cardElevated, in: Capsule())
            .overlay { Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1) }
            .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.saveState != .idle)
        .animation(.easeInOut(duration: 0.2), value: viewModel.saveState)
    }

    private var saveErrorTitle: String {
        (viewModel.saveError == .denied ? "share.save.denied_title" : "share.save.failed_title").localized
    }

    private static func saveErrorMessage(_ error: PhotoSaveError) -> String {
        switch error {
        case .denied: "share.save.denied_message".localized
        case .restricted: "share.save.restricted_message".localized
        case .failed: "share.save.failed_message".localized
        }
    }
}

/// One layer toggle of the preview sheet.
struct ShareLayerChip: View {
    let key: String
    @Binding var isOn: Bool
    var isEnabled = true

    init(_ key: String, isOn: Binding<Bool>, isEnabled: Bool = true) {
        self.key = key
        self._isOn = isOn
        self.isEnabled = isEnabled
    }

    var body: some View {
        Button {
            isOn.toggle()
            HapticManager.shared.light()
        } label: {
            HStack(spacing: 6) {
                // Always laid out, only faded: a chip that changed width on toggle made the
                // flow layout move its neighbours between rows.
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .opacity(isOn ? 1 : 0)
                Text(key.localized)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(isOn ? DesignSystem.Colors.textOnTint : DesignSystem.Colors.textSecondary)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(isOn ? DesignSystem.Colors.tint : DesignSystem.Colors.cardElevated, in: Capsule())
            .overlay {
                Capsule().stroke(isOn ? DesignSystem.Colors.tint : Color.white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The rendered image and its message, handed to the system share sheet.
private struct SharePayload: Identifiable {
    let id = UUID()
    let image: UIImage
    let message: String
}

/// The share card drawn at its full 1080 × 1920 layout and scaled down to `width`.
struct WorkoutShareCardThumbnail: View {
    let model: WorkoutShareCardModel
    let width: CGFloat

    var body: some View {
        ShareCardScaled(width: width) { WorkoutShareCardView(model: model) }
    }
}

/// Any 1080 × 1920 share card scaled down to `width`, in dark mode.
struct ShareCardScaled<Content: View>: View {
    let width: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        let scale = width / WorkoutShareCardView.size.width
        content
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: width, height: WorkoutShareCardView.size.height * scale, alignment: .topLeading)
            .environment(\.colorScheme, .dark)
            .accessibilityHidden(true)
    }
}

/// `UIActivityViewController` for SwiftUI. Saving to Photos from it needs
/// `NSPhotoLibraryAddUsageDescription`, which the app target declares.
private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

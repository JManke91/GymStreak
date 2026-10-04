//
//  HistoryImportView.swift
//  GymStreak
//
//  The Strong import sheet (docs/history-import.md §5). Self-contained so any
//  entry point — Settings today, the first-run fork later — presents it with
//  `HistoryImportView(viewModel: dependencies.makeHistoryImportViewModel())`.
//

import SwiftUI
import UniformTypeIdentifiers

struct HistoryImportView: View {

    @State var viewModel: HistoryImportViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isPickingFile = false

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                content
            }
            .navigationTitle("history_import.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !isFinished {
                        Button("common.cancel".localized) { dismiss() }
                            .disabled(viewModel.isBusy)
                    }
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isBusy)
        // On the stable root, one importer per hierarchy node — a known cause of a
        // picker failing to present when attached to conditional content.
        .fileImporter(
            isPresented: $isPickingFile,
            allowedContentTypes: [.commaSeparatedText, .plainText]
        ) { result in
            Task { await viewModel.fileSelected(result) }
        }
    }

    private var isFinished: Bool {
        if case .finished = viewModel.phase { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .intro:
            message(
                icon: "square.and.arrow.down",
                title: "history_import.intro.title".localized,
                body: "history_import.intro.body".localized
            ) {
                OnyxButton("history_import.intro.choose".localized, icon: "doc") { isPickingFile = true }
            }
        case .reading:
            ProgressView("history_import.reading".localized)
                .tint(DesignSystem.Colors.tint)
        case .preview(let preview):
            HistoryImportPreviewContent(
                preview: preview,
                weightUnit: $viewModel.weightUnit
            ) {
                Task { await viewModel.startImport() }
            }
        case .importing(let progress):
            VStack(spacing: DesignSystem.Spacing.lg) {
                ProgressView(value: progress)
                    .tint(DesignSystem.Colors.tint)
                Text("history_import.importing".localized)
                    .font(.onyxSubheadline)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .padding(DesignSystem.Spacing.xl)
        case .finished(let result):
            HistoryImportResultContent(result: result) { dismiss() }
        case .failed(let error):
            message(
                icon: "exclamationmark.triangle",
                title: "history_import.error.title".localized,
                body: Self.message(for: error)
            ) {
                OnyxButton("history_import.error.retry".localized, icon: "doc") {
                    viewModel.reset()
                    isPickingFile = true
                }
            }
        }
    }

    private func message(
        icon: String,
        title: String,
        body: String,
        @ViewBuilder action: () -> some View
    ) -> some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.tint)
            Text(title)
                .font(.onyxTitle2)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .multilineTextAlignment(.center)
            Text(body)
                .font(.onyxBody)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
            action()
                .padding(.top, DesignSystem.Spacing.sm)
        }
        .padding(DesignSystem.Spacing.xl)
    }

    private static func message(for error: HistoryImportError) -> String {
        switch error {
        case .unreadableFile: "history_import.error.unreadable".localized
        case .notAStrongExport: "history_import.error.not_strong".localized
        case .malformedRow(let line): "history_import.error.malformed".localized(line)
        case .noWorkouts: "history_import.error.empty".localized
        case .writeFailed: "history_import.error.write".localized
        }
    }
}

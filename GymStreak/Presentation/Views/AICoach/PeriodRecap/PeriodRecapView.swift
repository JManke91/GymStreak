//
//  PeriodRecapView.swift
//  GymStreak
//
//  Full-screen AI period recap pushed from HistoryView.
//  Handles loading, streaming, success, unavailable, insufficient, and error states.
//
//  Layout stability contract
//  ─────────────────────────
//  Both `.streaming` and `.success` render the **identical card tree**:
//    statStrip → headlineCard → trendsCard → correlationCard → closingCard
//  Each card pre-reserves vertical space via `minHeight` so snapshots (~30 Hz)
//  never cause neighbouring cards to reflow. Placeholder bars cross-dissolve
//  into streaming text on a discrete `content.isEmpty` transition — not on
//  every snapshot — so the animation cost is O(1) per field, not O(tokens).
//

import SwiftUI
import SwiftData
import Charts

struct PeriodRecapView: View {

    // MARK: - Init

    let initialRange: PeriodRange

    // MARK: - State

    @State private var viewModel: PeriodRecapViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    init(initialRange: PeriodRange) {
        self.initialRange = initialRange
        self._viewModel = State(
            initialValue: PeriodRecapViewModel(initialRange: initialRange)
        )
    }

    // MARK: - minHeight constants (calibrated for 14pt body, lineSpacing 5, ~320pt content width)

    private enum CardHeight {
        /// 20pt bold headline, wraps to 2 lines max
        static let headline: CGFloat = 60
        /// 3-6 sentence trends narrative
        static let trends: CGFloat = 140
        /// 2-3 sentence correlation callout
        static let correlation: CGFloat = 90
        /// 1 sentence closing
        static let closing: CGFloat = 44
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            DesignSystem.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    topNav
                    titleBlock
                    rangeChipRow
                    mainContent
                }
                .padding(.top, 8)
            }
            .safeAreaPadding(.bottom, 24)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.load(modelContext: modelContext)
        }
    }

    // MARK: - Top Nav

    private var topNav: some View {
        HStack {
            Button {
                HapticManager.shared.light()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ai_coach.period_recap.nav.back".localized)

            Spacer()
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Title Block

    @ViewBuilder
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Eyebrow
            HStack(spacing: 6) {
                AISparkleView(size: 20, color: AICoachTheme.accent, glow: isStreaming, pulse: isStreaming)
                Text(isStreaming ? "ai_coach.period_recap.eyebrow.streaming".localized : "ai_coach.period_recap.eyebrow.static".localized)
                    .font(AICoachTheme.mono(size: 11))
                    .foregroundStyle(AICoachTheme.accent)
                    .kerning(1.4)
                    .animation(.easeInOut(duration: 0.25), value: isStreaming)
            }

            // Large period label
            Text(viewModel.range.label(locale: locale))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .kerning(-0.5)
                .foregroundStyle(Color.white)

            // Cache state sub-row (success only)
            if case .success(_, let isCached, let generatedAt, _) = viewModel.state {
                cacheSubrow(isCached: isCached, generatedAt: generatedAt)
            }
        }
        .padding(.horizontal, 20)
    }

    private func cacheSubrow(isCached: Bool, generatedAt: Date) -> some View {
        HStack(spacing: 4) {
            if isCached {
                Text("ai_coach.period_recap.cache.from_cache".localized)
                    .font(AICoachTheme.mono(size: 10, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.35))
                Text("·")
                    .font(AICoachTheme.mono(size: 10, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.2))
                Text(relativeDate(generatedAt))
                    .font(AICoachTheme.mono(size: 10, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.35))
                Text("·")
                    .font(AICoachTheme.mono(size: 10, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.2))
                Button {
                    Task { await viewModel.regenerate(modelContext: modelContext) }
                } label: {
                    Text("ai_coach.period_recap.cache.regenerate".localized)
                        .font(AICoachTheme.mono(size: 10, weight: .regular))
                        .foregroundStyle(AICoachTheme.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Range Chip Row

    private var rangeChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PeriodRange.allCases) { range in
                    rangeChip(for: range)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func rangeChip(for range: PeriodRange) -> some View {
        let isActive = viewModel.range == range
        return Button {
            if !isActive {
                HapticManager.shared.selection()
                Task { await viewModel.setRange(range, modelContext: modelContext) }
            }
        } label: {
            Text(chipLabel(for: range))
                .font(.system(size: 13, weight: isActive ? .semibold : .regular, design: .rounded))
                .foregroundStyle(isActive ? Color.black : Color.white.opacity(0.70))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isActive ? Color.white : Color.white.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: viewModel.range)
    }

    private func chipLabel(for range: PeriodRange) -> String {
        switch range {
        case .thisWeek: return "ai_coach.period_recap.chip.this_week".localized
        case .lastWeek: return "ai_coach.period_recap.chip.last_week".localized
        case .thisMonth: return "ai_coach.period_recap.chip.this_month".localized
        case .lastMonth: return "ai_coach.period_recap.chip.last_month".localized
        case .lastThreeMonths: return "ai_coach.period_recap.chip.last_3_months".localized
        case .thisYear: return "ai_coach.period_recap.chip.this_year".localized
        }
    }

    // MARK: - Main Content (state-driven)

    @ViewBuilder
    private var mainContent: some View {
        switch viewModel.state {
        case .loading:
            loadingView
        case .streaming(let partial):
            recapCardTree(
                headlineContent: partial.headline,
                trendsContent: partial.trendsNarrative,
                correlationContent: partial.correlationHighlight,
                closingContent: partial.closingSentence,
                metrics: partial.headlineMetrics,
                showCorrelationWhenEmpty: true,
                isStreaming: true,
                footerContent: { AnyView(streamingFooter) },
                privacyFooter: false
            )
        case .success(let output, _, _, let metrics):
            recapCardTree(
                headlineContent: output.headline,
                trendsContent: output.trendsNarrative,
                correlationContent: output.correlationHighlight,
                closingContent: output.closingSentence,
                metrics: metrics,
                showCorrelationWhenEmpty: false,
                isStreaming: false,
                footerContent: { AnyView(EmptyView()) },
                privacyFooter: true
            )
        case .unavailable(let metrics):
            unavailableView(metrics: metrics)
        case .insufficient(let metrics):
            insufficientView(metrics: metrics)
        case .error(let msg):
            errorView(message: msg)
        }
    }

    // MARK: - Unified Card Tree
    //
    // Both streaming and success render the same card order:
    //   statStrip → headlineCard → trendsCard → correlationCard → closingCard
    //
    // Each card pre-reserves vertical space so ~30 Hz snapshots never cause
    // neighbouring cards to reflow.

    private func recapCardTree(
        headlineContent: String,
        trendsContent: String,
        correlationContent: String?,
        closingContent: String,
        metrics: HeadlineMetrics?,
        showCorrelationWhenEmpty: Bool,
        isStreaming: Bool,
        footerContent: () -> AnyView,
        privacyFooter: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {

            // 1. Stat strip — always first in both states
            statStrip(
                sessions: metrics?.totalSessions,
                volumeKg: metrics?.totalVolumeKg,
                prs: nil,
                isStreaming: isStreaming && metrics == nil
            )

            // 2. Headline card
            headlineCardSlot(content: headlineContent, isStreaming: isStreaming)

            // 3. Trends card
            sectionCardSlot(
                label: "ai_coach.period_recap.section.trends".localized,
                content: trendsContent,
                minHeight: CardHeight.trends,
                isStreaming: isStreaming
            )

            // 4. Correlation card
            // During streaming: render when the field is non-nil (may still be empty string mid-stream).
            // In success: omit entirely when nil (section hidden per schema Optional).
            if showCorrelationWhenEmpty || correlationContent != nil {
                correlationCardSlot(content: correlationContent ?? "", isStreaming: isStreaming)
            }

            // 5. Closing card
            sectionCardSlot(
                label: "ai_coach.period_recap.section.closing".localized,
                content: closingContent,
                minHeight: CardHeight.closing,
                isStreaming: isStreaming
            )

            footerContent()

            if privacyFooter {
                AIPrivacyFooter(tone: .full)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Loading State

    private var loadingView: some View {
        VStack(spacing: 16) {
            skeletonStatStrip
            skeletonSection
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Unavailable State

    private func unavailableView(metrics: HeadlineMetrics?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let m = metrics {
                statStrip(sessions: m.totalSessions, volumeKg: m.totalVolumeKg, prs: nil, isStreaming: false)
            }
            FallbackHintLine(text: "ai_coach.period_recap.fallback.unavailable".localized)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Insufficient State

    private func insufficientView(metrics: HeadlineMetrics) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            statStrip(sessions: metrics.totalSessions, volumeKg: metrics.totalVolumeKg, prs: nil, isStreaming: false)
            FallbackHintLine(text: "ai_coach.period_recap.fallback.insufficient".localized)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Error State

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            FallbackHintLine(text: "ai_coach.period_recap.error.banner".localized)
            Button {
                Task { await viewModel.regenerate(modelContext: modelContext) }
            } label: {
                Text("ai_coach.period_recap.error.retry".localized)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignSystem.Colors.textOnTint)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AICoachTheme.accent)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Stat Strip

    private func statStrip(sessions: Int?, volumeKg: Double?, prs: Int?, isStreaming: Bool) -> some View {
        HStack(spacing: 0) {
            statCell(
                value: sessions.map { "\($0)" },
                label: "ai_coach.period_recap.stat.sessions".localized,
                tinted: false,
                isStreaming: isStreaming && sessions == nil
            )
            Divider().background(Color.white.opacity(0.06)).frame(height: 36)
            statCell(
                value: volumeKg.map { formatVolume($0) },
                label: "ai_coach.period_recap.stat.volume".localized,
                tinted: true,
                isStreaming: isStreaming && volumeKg == nil
            )
            Divider().background(Color.white.opacity(0.06)).frame(height: 36)
            statCell(
                value: prs.map { "\($0)" },
                label: "ai_coach.period_recap.stat.prs".localized,
                tinted: false,
                isStreaming: isStreaming
            )
        }
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private func statCell(value: String?, label: String, tinted: Bool, isStreaming: Bool) -> some View {
        VStack(spacing: 3) {
            if isStreaming {
                AISkeletonBar(width: 44, height: 18, cornerRadius: 5)
            } else {
                Text(value ?? "-")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(tinted ? AICoachTheme.accent : Color.white)
            }
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Headline Card Slot

    /// Renders the headline with a minHeight-reserved frame.
    /// Placeholder bars cross-dissolve to streaming text on the discrete
    /// `content.isEmpty` boolean — not on every snapshot.
    private func headlineCardSlot(content: String, isStreaming: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            placeholderBars
                .opacity(content.isEmpty ? 1 : 0)

            Text(content)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
                .lineSpacing(4)
                .animation(nil, value: content)
                .opacity(content.isEmpty ? 0 : 1)
        }
        .frame(minHeight: CardHeight.headline, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.25), value: content.isEmpty)
    }

    // MARK: - Section Card Slot (Trends / Closing)

    /// Renders a labelled AISurface card with placeholder → streaming cross-dissolve.
    private func sectionCardSlot(
        label: String,
        content: String,
        minHeight: CGFloat,
        isStreaming: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(label)
            AISurface(isStreaming: isStreaming && !content.isEmpty, showFooter: false, compact: true) {
                ZStack(alignment: .topLeading) {
                    placeholderBars
                        .opacity(content.isEmpty ? 1 : 0)

                    StreamingTextView(
                        text: content,
                        isStreaming: isStreaming,
                        font: .system(size: 14)
                    )
                    .opacity(content.isEmpty ? 0 : 1)
                }
                .frame(minHeight: minHeight, alignment: .topLeading)
                .animation(.easeInOut(duration: 0.25), value: content.isEmpty)
            }
        }
    }

    // MARK: - Correlation Card Slot

    private func correlationCardSlot(content: String, isStreaming: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("ai_coach.period_recap.section.correlation".localized)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AICoachTheme.warningAccent.opacity(0.85))
                    Text("ai_coach.period_recap.correlation.label".localized)
                        .font(AICoachTheme.mono(size: 9))
                        .foregroundStyle(AICoachTheme.warningAccent.opacity(0.85))
                        .kerning(1.4)
                }
                ZStack(alignment: .topLeading) {
                    placeholderBars
                        .opacity(content.isEmpty ? 1 : 0)
                    StreamingTextView(
                        text: content,
                        isStreaming: isStreaming,
                        font: .system(size: 14)
                    )
                    .opacity(content.isEmpty ? 0 : 1)
                }
                .frame(minHeight: CardHeight.correlation, alignment: .topLeading)
                .animation(.easeInOut(duration: 0.25), value: content.isEmpty)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: AICoachTheme.warningAccent.opacity(0.18), location: 0.00),
                                    .init(color: AICoachTheme.warningAccent.opacity(0.03), location: 0.40),
                                    .init(color: Color.white.opacity(0.03), location: 1.00),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: AICoachTheme.warningAccent.opacity(0.07), location: 0.00),
                                    .init(color: Color.white.opacity(0.02), location: 1.00),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .padding(1.5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    // MARK: - Streaming Footer

    private var streamingFooter: some View {
        HStack(spacing: 8) {
            PeriodRecapPulsingDots()
            Text("ai_coach.period_recap.streaming.remaining".localized)
                .font(AICoachTheme.mono(size: 10, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .padding(.top, 4)
    }

    // MARK: - Skeleton Helpers

    private var skeletonStatStrip: some View {
        statStrip(sessions: nil, volumeKg: nil, prs: nil, isStreaming: true)
    }

    private var skeletonSection: some View {
        AISurface(isStreaming: true, showFooter: false, compact: true) {
            VStack(alignment: .leading, spacing: 8) {
                AISkeletonBar()
                AISkeletonBar(width: 240)
                AISkeletonBar(width: 190)
            }
        }
    }

    // MARK: - Placeholder Bars

    /// Three muted bars shown while a field has not yet received any content.
    private var placeholderBars: some View {
        VStack(alignment: .leading, spacing: 8) {
            AISkeletonBar()
            AISkeletonBar(width: 220)
            AISkeletonBar(width: 180)
        }
        .opacity(0.08)
    }

    // MARK: - Section Label

    /// `.drawingGroup()` rasterises the kerned+uppercase text as a single CALayer,
    /// preventing the "garbled characters" glitch during ancestor layout animations.
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.35))
            .kerning(0.8)
            .textCase(.uppercase)
            .drawingGroup()
    }

    // MARK: - Convenience

    private var isStreaming: Bool {
        if case .streaming = viewModel.state { return true }
        return false
    }

    private func formatVolume(_ kg: Double) -> String {
        if kg >= 1000 {
            return String(format: "%.1ft", kg / 1000)
        } else {
            return String(format: "%.0fkg", kg)
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        return "vor " + formatter.localizedString(for: date, relativeTo: Date())
            .replacingOccurrences(of: "vor ", with: "")
    }
}

// MARK: - Pulsing Dots

private struct PeriodRecapPulsingDots: View {
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(AICoachTheme.accent)
                    .frame(width: 4, height: 4)
                    .opacity(reduceMotion ? 0.5 : dotOpacity(index: i))
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    private func dotOpacity(index: Int) -> Double {
        let base = 0.25 + Double(index) * 0.25
        return phase > 0.5 ? min(1.0, base + 0.4) : base
    }
}

//
//  CoachChatView.swift
//  GymStreak
//
//  Minimal chat surface for the AI Coach chat spike. Message list + input bar,
//  an empty state with 3 tappable starter questions, and the on-device privacy
//  footer. The bubbles themselves live in `CoachChatMessageBubble.swift`.
//  See docs/ai-coach-chat-feasibility.md, and docs/pro-subscription.md §5e for
//  the free monthly message allowance.
//

import SwiftUI

/// Environment-facing wrapper: resolves the composition root and hands the
/// dependencies to the view that owns the ViewModel, so the ViewModel is built
/// with injected collaborators rather than singletons (Hard rule 2). Same shape
/// as `ExerciseProgressChartView`.
struct CoachChatView: View {

    @EnvironmentObject private var dependencies: AppDependencies

    var body: some View {
        CoachChatViewInternal(
            allowanceGate: dependencies.makeAICoachAllowanceGate(for: .coachChat),
            routineDraftViewModel: dependencies.makeRoutineDraftViewModel()
        )
    }
}

private struct CoachChatViewInternal: View {

    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.weightUnit) private var weightUnit
    @State private var viewModel: CoachChatViewModel
    /// Owned here rather than by the sheet so the exercise library can be loaded on the
    /// chip tap, before the sheet starts animating in, and so the drafting service (and
    /// with it the `LanguageModelSession`) survives across one visit to the chat.
    ///
    /// A drafting *session* does not survive a dismissal: `sheetWasDismissed()` drops the
    /// allowance ticket along with the draft, so reopening the sheet starts a new session
    /// and reserves a new unit. See docs/ai-coach-routine-drafting.md §8.
    @State private var routineDraftViewModel: RoutineDraftViewModel
    @State private var isShowingRoutineDraft = false
    @FocusState private var inputFocused: Bool

    init(allowanceGate: AICoachAllowanceGate, routineDraftViewModel: RoutineDraftViewModel) {
        self._viewModel = State(wrappedValue: CoachChatViewModel(allowanceGate: allowanceGate))
        self._routineDraftViewModel = State(wrappedValue: routineDraftViewModel)
    }

    var body: some View {
        ZStack {
            DesignSystem.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                messageList
                inputBar
            }
        }
        .navigationTitle("ai_coach.chat.title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                .accessibilityLabel("ai_coach.chat.close".localized)
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    AICoachSettingsView()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                .accessibilityLabel("ai_coach.settings.open".localized)
            }
#if DEBUG
            // Phase 0 auto-drill trigger (docs/ai-coach-chat-plan.md) — never ships.
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.runPhaseZeroDrill()
                } label: {
                    Image(systemName: "ladybug")
                        .foregroundStyle(AICoachTheme.accent)
                }
                .accessibilityLabel("Run Phase 0 drill")
                .disabled(viewModel.isDrillRunning || viewModel.isResponding)
            }
#endif
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.reset()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(AICoachTheme.accent)
                }
                .accessibilityLabel("ai_coach.chat.new_chat".localized)
                .disabled(viewModel.isEmptyConversation && !viewModel.isResponding)
            }
        }
        .onAppear {
            viewModel.onAppear(
                weightUnit: weightUnit,
                makeFactProvider: dependencies.makeChatFactProvider
            )
        }
        .sheet(isPresented: $isShowingRoutineDraft, onDismiss: {
            // Ends the drafting session however it ended — Create, Discard, or a swipe
            // away mid-stream. Cancels any generation still running and gives back a
            // unit that bought nothing.
            routineDraftViewModel.sheetWasDismissed()
        }) {
            RoutineDraftSheet(viewModel: routineDraftViewModel)
        }
        // In-flight streams are cancelled by the presenting fullScreenCover's
        // onDismiss (ContentView) — not here, so pushing settings on top of the
        // chat doesn't kill a streaming answer.
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if viewModel.isEmptyConversation {
                        emptyState
                    } else {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }

                    AIPrivacyFooter(tone: .full)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                        .id(Self.footerId)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.last?.text) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let lastId = viewModel.messages.last?.id else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(lastId, anchor: .bottom)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                AISparkleView(size: 30, glow: true)
                    .accessibilityHidden(true)
                Text("ai_coach.chat.empty.title".localized)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.white)
                Text("ai_coach.chat.empty.subtitle".localized)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            .padding(.top, 24)
            .padding(.bottom, 4)

            ForEach(viewModel.suggestedQuestions, id: \.self) { question in
                Button {
                    inputFocused = false
                    viewModel.send(suggestion: question)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AICoachTheme.accent)
                        Text(question)
                            .font(.system(size: 15))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 13)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(AICoachTheme.accent.opacity(0.18), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.isAvailable)
            }
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider().background(Color.white.opacity(0.06))

            // §8 placement D — the free-tier allowance hint. Not a paywall: it
            // blocks nothing and swallows no taps, and it sits above the field
            // so it is on screen *before* the send that hits the gate.
            if let nudge = viewModel.allowanceNudge {
                OnyxCapNudge(text: nudge.text, used: nudge.used, limit: nudge.limit)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
            }

            if viewModel.isAvailable {
                // The routine-drafting entry point. Present only while the coach is —
                // exactly as the coach bar is — because a device that cannot run Apple
                // Intelligence must not be offered a feature that needs it.
                buildRoutineChip

                HStack(spacing: 10) {
                    TextField(
                        "ai_coach.chat.input.placeholder".localized,
                        text: $viewModel.inputText,
                        axis: .vertical
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.white)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit(sendIfPossible)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )

                    sendButton
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            } else {
                Text("ai_coach.chat.unavailable".localized)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(16)
            }
        }
        .background(DesignSystem.Colors.background)
    }

    /// Opens the drafting sheet — but only once the preflight says it may open. The
    /// order (availability, then the routine cap) lives in the ViewModel: an ineligible
    /// device never reaches a paywall, and a free user already at the cap is stopped
    /// *before* typing a description for a routine that could not be saved.
    private var buildRoutineChip: some View {
        Button {
            inputFocused = false
            if routineDraftViewModel.requestDrafting() {
                isShowingRoutineDraft = true
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AICoachTheme.accent)
                Text("ai_coach.routine_draft.chip".localized)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 14)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        Capsule()
                            .strokeBorder(AICoachTheme.accent.opacity(0.18), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private var sendButton: some View {
        Button(action: buttonAction) {
            Image(systemName: viewModel.isResponding ? "stop.fill" : "arrow.up")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.textOnTint)
                .frame(width: 34, height: 34)
                .background(
                    Circle().fill(
                        viewModel.isResponding || viewModel.canSend
                            ? AICoachTheme.accent
                            : AICoachTheme.accent.opacity(0.3)
                    )
                )
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.isResponding && !viewModel.canSend)
        .accessibilityLabel(
            viewModel.isResponding
                ? "ai_coach.chat.stop".localized
                : "ai_coach.chat.send".localized
        )
    }

    private func buttonAction() {
        if viewModel.isResponding {
            viewModel.cancel()
        } else {
            sendIfPossible()
        }
    }

    private func sendIfPossible() {
        guard viewModel.canSend else { return }
        viewModel.send()
    }

    private static let footerId = "coach-chat-privacy-footer"
}

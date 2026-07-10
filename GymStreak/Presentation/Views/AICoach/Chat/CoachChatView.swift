//
//  CoachChatView.swift
//  GymStreak
//
//  Minimal chat surface for the AI Coach chat spike. Message bubbles + input bar,
//  an empty state with 3 tappable starter questions, and the on-device privacy
//  footer. Reuses `StreamingTextView` for the live assistant reply.
//  See docs/ai-coach-chat-feasibility.md.
//

import SwiftUI

struct CoachChatView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = CoachChatViewModel()
    @FocusState private var inputFocused: Bool

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
        .onAppear { viewModel.onAppear(modelContext: modelContext) }
        .onDisappear { viewModel.cancel() }
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

            if viewModel.isAvailable {
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

// MARK: - Message bubble

private struct MessageBubble: View {

    let message: CoachChatMessage

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundStyle(DesignSystem.Colors.textOnTint)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(AICoachTheme.accent)
                    )
            }
        case .assistant:
            HStack {
                assistantContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 40)
            }
        }
    }

    @ViewBuilder
    private var assistantContent: some View {
        switch message.phase {
        case .streaming:
            AISurface(isStreaming: true, showFooter: false, compact: true) {
                StreamingTextView(text: message.text, isStreaming: true)
            }
        case .final:
            AISurface(isStreaming: false, showFooter: false, compact: true) {
                StreamingTextView(text: message.text, isStreaming: false)
            }
        case .failed:
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 13))
                    .foregroundStyle(DesignSystem.Colors.warning)
                Text(message.text)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
        }
    }
}

//
//  RoutineDraftCreatedView.swift
//  GymStreak
//
//  The drafting sheet's last face: the routine was written, and the person sees it land —
//  a checkmark drawing itself inside a glow, the name they chose, and the exercises
//  arriving one by one — instead of the sheet closing on them silently.
//  See docs/ai-coach-routine-drafting.md §9b.
//
//  Presentational only: it takes a finished `CreatedRoutineSummary`, formats and counts
//  nothing, and reports Done through a closure.
//

import SwiftUI

struct RoutineDraftCreatedView: View {

    let summary: CreatedRoutineSummary
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Flipped once on appear; every element keys its own delayed animation off it, which
    /// is what staggers the entrance without a timer.
    @State private var isRevealed = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                hero
                    .padding(.top, 36)

                headline

                exerciseCard

                Text("ai_coach.routine_draft.created.message".localized)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .reveal(isRevealed, delay: 0.55 + 0.07 * Double(summary.exercises.count), reduceMotion: reduceMotion)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            doneButton
        }
        .sensoryFeedback(.success, trigger: isRevealed)
        .onAppear {
            // The transaction carries the checkmark's insertion (the draw-on); every other
            // element overrides it with its own staggered `.animation(_:value:)`.
            withAnimation(.easeOut(duration: 0.4).delay(0.15)) { isRevealed = true }
        }
    }

    // MARK: - Hero

    /// A checkmark drawn on inside a soft accent glow, with two rings rippling out once.
    private var hero: some View {
        ZStack {
            RadialGradient(
                colors: [AICoachTheme.accent.opacity(0.28), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 90
            )
            .frame(width: 180, height: 180)
            .blur(radius: 14)
            .opacity(isRevealed ? 1 : 0)
            .animation(.easeOut(duration: 0.6), value: isRevealed)

            if !reduceMotion {
                ripple(delay: 0.2)
                ripple(delay: 0.45)
            }

            Circle()
                .fill(AICoachTheme.accent.opacity(0.14))
                .overlay(Circle().strokeBorder(AICoachTheme.accent.opacity(0.45), lineWidth: 1.5))
                .frame(width: 104, height: 104)
                .scaleEffect(isRevealed || reduceMotion ? 1 : 0.5)
                .opacity(isRevealed ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.62), value: isRevealed)

            checkmark

            AISparkleView(size: 18, glow: true)
                .offset(x: 50, y: -46)
                .scaleEffect(isRevealed || reduceMotion ? 1 : 0.2)
                .opacity(isRevealed ? 1 : 0)
                .animation(.spring(response: 0.45, dampingFraction: 0.55).delay(0.4), value: isRevealed)
        }
        .frame(height: 150)
        .accessibilityHidden(true)
    }

    /// Inserted on reveal so the SF Symbols 7 Draw On transition (iOS 26) traces it in —
    /// the insertion is the trigger. Symbol effects already simplify under Reduce Motion.
    private var checkmark: some View {
        ZStack {
            if isRevealed {
                Image(systemName: "checkmark")
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(AICoachTheme.accent)
                    .transition(.symbolEffect(.drawOn))
            }
        }
        .frame(width: 60, height: 60)
    }

    /// One expanding, fading ring. Plays once: it is driven by `isRevealed`, which only
    /// ever flips on.
    private func ripple(delay: Double) -> some View {
        Circle()
            .stroke(AICoachTheme.accent.opacity(0.5), lineWidth: 1.5)
            .frame(width: 104, height: 104)
            .scaleEffect(isRevealed ? 1.75 : 1)
            .opacity(isRevealed ? 0 : 0.8)
            .animation(.easeOut(duration: 1.2).delay(delay), value: isRevealed)
    }

    // MARK: - Headline

    private var headline: some View {
        VStack(spacing: 10) {
            Text("ai_coach.routine_draft.created.eyebrow".localized)
                .font(.system(size: 12, weight: .semibold))
                .tracking(2.5)
                .foregroundStyle(AICoachTheme.accent)

            Text(summary.name)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(summary.totals)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .reveal(isRevealed, delay: 0.3, reduceMotion: reduceMotion)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("ai_coach.routine_draft.created.accessibility".localized(summary.name))
        .accessibilityValue(summary.totals)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Exercises

    /// The exercises as the review list last showed them, each arriving a beat after the
    /// one before. Lazy because it is the user-scaled part of the screen.
    private var exerciseCard: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(summary.exercises) { exercise in
                exerciseRow(exercise)
                    .reveal(isRevealed, delay: 0.38 + 0.07 * Double(exercise.number), reduceMotion: reduceMotion)

                if !exercise.isLast {
                    Divider()
                        .background(Color.white.opacity(0.06))
                        .padding(.leading, 52)
                }
            }
        }
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: AICoachTheme.surfaceCorner, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AICoachTheme.surfaceCorner, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func exerciseRow(_ exercise: CreatedRoutineSummary.Entry) -> some View {
        HStack(spacing: 14) {
            Text("\(exercise.number)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                // Never white on the tint.
                .foregroundStyle(DesignSystem.Colors.textOnTint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(AICoachTheme.accent))

            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(exercise.summary)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.55))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Done

    private var doneButton: some View {
        Button(action: onDone) {
            Text("ai_coach.routine_draft.created.done".localized)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.textOnTint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AICoachTheme.accent)
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(DesignSystem.Colors.background.ignoresSafeArea(edges: .bottom))
        .reveal(isRevealed, delay: 0.6, reduceMotion: reduceMotion)
    }
}

// MARK: - Staggered reveal

private extension View {

    /// Fades and lifts the view in `delay` seconds after `isRevealed` flips. With Reduce
    /// Motion it only fades, and without the delay chain.
    func reveal(_ isRevealed: Bool, delay: Double, reduceMotion: Bool) -> some View {
        self
            .opacity(isRevealed ? 1 : 0)
            .offset(y: isRevealed || reduceMotion ? 0 : 14)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.25)
                    : .spring(response: 0.5, dampingFraction: 0.82).delay(delay),
                value: isRevealed
            )
    }
}

// The success face is unreachable in the simulator (no on-device model), so the canvas is
// where its motion gets looked at.
#Preview {
    RoutineDraftCreatedView(
        summary: CreatedRoutineSummary(
            name: "Upper A",
            exerciseCount: 3,
            setCount: 10,
            rows: [
                RoutineDraftRow(id: UUID(), name: "Squat", summary: "4 sets • 5 reps • 100 kg", hint: nil, canMoveUp: false, canMoveDown: true),
                RoutineDraftRow(id: UUID(), name: "Bench Press", summary: "3 sets • 8 reps • 60 kg", hint: nil, canMoveUp: true, canMoveDown: true),
                RoutineDraftRow(id: UUID(), name: "Row", summary: "3 sets • 10 reps • 50 kg", hint: nil, canMoveUp: true, canMoveDown: false),
            ]
        ),
        onDone: {}
    )
    .background(DesignSystem.Colors.background)
    .preferredColorScheme(.dark)
}

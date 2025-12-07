//
//  CompactActionBar.swift
//  GymStreakWatch Watch App
//
//  Combined action bar with Complete button and set navigation
//  Optimized for minimal vertical space usage
//

import SwiftUI
import WatchKit

struct CompactActionBar: View {
    let exerciseName: String?
    let isCompleted: Bool
    let currentSetIndex: Int
    let totalSets: Int
    let onComplete: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    // New: closure to advance to next exercise when there is no next set in current exercise
    let onAdvance: () -> Void

    private var hasPrevious: Bool {
        currentSetIndex > 0
    }

    private var hasNext: Bool {
        currentSetIndex < totalSets - 1
    }

    var body: some View {
        if totalSets > 1 {
            // Multi-set layout: Prev + Complete + Next
            HStack(spacing: 4) {
                // Previous button
                Button {
                    onPrevious()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .controlSize(.mini)
                .disabled(!hasPrevious)
                .opacity(hasPrevious ? 1.0 : 0.3)

                Spacer()

                // Complete button
                ZStack {
                    // Put visuals inside the Button label so the entire area responds to taps
                    Button {
                        // IMPORTANT: decide navigation based on prior state (isCompleted).
                        // If the set is already completed, treat this as an "uncomplete" -> do NOT navigate.
                        if isCompleted {
                            // Uncomplete case: only toggle state / haptic
                            handleComplete()
                        } else {
                            // Complete case: toggle then advance appropriately
                            handleComplete()
                            if hasNext {
                                onNext()
                            } else {
                                onAdvance()
                            }
                        }
                    } label: {
                        VStack(spacing: 0) {
                            ZStack {
                                Image(systemName: "circle")
                                    .font(.system(size: 40))

                                // Subtle translucent background when completed to keep visual cue
                                if isCompleted {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 30, height: 30)
                                        .opacity(0.32)
                                }

                                // Set index overlay text (kept small)
                                HStack(spacing: 0) {
                                    Text("\(currentSetIndex + 1)/")
                                        .font(.system(size: 14))
                                    Text("\(totalSets)")
                                        .font(.system(size: 8))
                                }
                            }
                            // Explicitly increase hit area for watch: full tappable rectangle
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())

                            Text(exerciseName ?? "")
                                .font(.system(size: 12, weight: .light))
                        }
//                        .frame(minWidth: 68, minHeight: 44)

                    }
                    .controlSize(.mini)
                    .buttonStyle(.plain)
                    .accessibilityLabel(isCompleted ? "Set completed. Tap to mark incomplete" : "Complete set")
                }

                Spacer()

                // Next button
                Button {
                    onNext()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .controlSize(.mini)
                .disabled(!hasNext)
                .opacity(hasNext ? 1.0 : 0.3)
            }
            .padding(.horizontal, 12)
        } else {
            // Single set layout: Full-width Complete button
            Button {
                // If already completed -> uncomplete only, don't advance.
                if isCompleted {
                    handleComplete()
                } else {
                    handleComplete()
                    // Single-set exercise - after completing, attempt to advance to next exercise
                    onAdvance()
                }
            } label: {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .symbolRenderingMode(.hierarchical)
            }
            .controlSize(.mini)
            .tint(isCompleted ? .green : .blue)
        }
    }

    private func handleComplete() {
        if isCompleted {
            WKInterfaceDevice.current().play(.directionDown)
        } else {
            WKInterfaceDevice.current().play(.success)
        }
        onComplete()
    }
}

// MARK: - Preview

//#Preview("Multi-set layout") {
//    ZStack {
//        Color.black.ignoresSafeArea()
//
//        VStack {
//            Spacer()
//            CompactActionBar(
//                isCompleted: false,
//                currentSetIndex: 1,
//                totalSets: 4,
//                onComplete: {},
//                onPrevious: {},
//                onNext: {}
//            )
//        }
//    }
//}

//#Preview("Single set layout") {
//    ZStack {
//        Color.black.ignoresSafeArea()
//
//        VStack {
//            Spacer()
//            CompactActionBar(
//                isCompleted: false,
//                currentSetIndex: 0,
//                totalSets: 1,
//                onComplete: {},
//                onPrevious: {},
//                onNext: {}
//            )
//        }
//    }
//}

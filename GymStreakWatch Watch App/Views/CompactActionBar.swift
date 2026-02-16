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
        VStack(spacing: 0) {
            if totalSets > 1 {
                // Multi-set layout: Prev + Complete + Next
                HStack(spacing: 4) {
                    // Previous button
                    Button {
                        onPrevious()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(!hasPrevious)
                    .opacity(hasPrevious ? 1.0 : 0.3)

                    Spacer()

                    // Complete button
                    Button {
                        handleComplete()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                                .font(.system(size: 16, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)

                            HStack(alignment: .firstTextBaseline, spacing: 0) {
                                Text("\(currentSetIndex + 1)")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("/\(totalSets)")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .monospacedDigit()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isCompleted ? .green : .blue)
                    .buttonBorderShape(.capsule)
                    .accessibilityLabel(isCompleted ? "Set completed. Tap to mark incomplete" : "Complete set")

                    Spacer()

                    // Next button
                    Button {
                        onNext()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(!hasNext)
                    .opacity(hasNext ? 1.0 : 0.3)
                }
                .padding(.horizontal, 12)
            } else {
                // Single set layout: Full-width Complete button
                Button {
                    handleComplete()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.system(size: 18, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                        Text(isCompleted ? "Done" : "Complete")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(isCompleted ? .green : .blue)
                .buttonBorderShape(.capsule)
            }

            // show current exercise name
            Text(exerciseName ?? "")
                .font(.system(size: 12, weight: .light))
                .lineLimit(1)
                .truncationMode(.tail)
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

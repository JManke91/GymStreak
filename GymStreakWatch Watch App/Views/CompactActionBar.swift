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
    let completedSets: [Bool]  // Completion status for each set (for dot coloring)
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

    private func dotColor(for index: Int) -> Color {
        if index == currentSetIndex {
            // Current set: blue if not completed, green if completed
            return isCompleted ? .green : .blue
        } else if index < completedSets.count && completedSets[index] {
            // Completed set: green
            return .green
        } else {
            // Incomplete set: gray
            return Color.gray.opacity(0.4)
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            if totalSets > 1 {
                // Multi-set layout: Dots on top, arrows beside button
                VStack(spacing: 4) {
                    // Progress dots (centered) - green for completed, blue for current, gray for incomplete
                    HStack(spacing: 4) {
                        ForEach(0..<totalSets, id: \.self) { index in
                            Circle()
                                .fill(dotColor(for: index))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.vertical, 2)

                    // Navigation arrows + Complete button row
                    HStack(spacing: 0) {
                        // Previous button - larger hit area
                        Button {
                            onPrevious()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .bold))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(hasPrevious ? .primary : .tertiary)
                        .disabled(!hasPrevious)

                        // Complete button - more compact
                        Button {
                            handleComplete()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                                    .font(.system(size: 16, weight: .semibold))
                                    .symbolRenderingMode(.hierarchical)

                                Text(isCompleted ? "Done" : "Set")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .frame(height: 32)
                            .padding(.horizontal, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(isCompleted ? .green : .blue)
                        .buttonBorderShape(.capsule)
                        .accessibilityLabel(isCompleted ? "Set \(currentSetIndex + 1) of \(totalSets) completed" : "Complete set \(currentSetIndex + 1) of \(totalSets)")

                        // Next button - larger hit area
                        Button {
                            onNext()
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 18, weight: .bold))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(hasNext ? .primary : .tertiary)
                        .disabled(!hasNext)
                    }
                }
                .padding(.horizontal, 0)
            } else {
                // Single set layout: Full-width Complete button with exercise name inside
                Button {
                    handleComplete()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.system(size: 16, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(isCompleted ? "Done" : "Set")
                                .font(.system(size: 13, weight: .semibold))
                            if let name = exerciseName, !name.isEmpty {
                                Text(name)
                                    .font(.system(size: 10, weight: .regular))
                                    .opacity(0.8)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .frame(height: 36)
                }
                .buttonStyle(.borderedProminent)
                .tint(isCompleted ? .green : .blue)
                .buttonBorderShape(.capsule)
            }
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

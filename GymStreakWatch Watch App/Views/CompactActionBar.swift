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
    let isCompleted: Bool
    let currentSetIndex: Int
    let totalSets: Int
    let onComplete: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void

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
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(!hasPrevious)
                .opacity(hasPrevious ? 1.0 : 0.3)
                .accessibilityLabel("Previous set")

                // Complete button
                Button {
                    handleComplete()
                } label: {
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .tint(isCompleted ? .green : .blue)
                .accessibilityLabel(isCompleted ? "Set completed" : "Complete set")

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
                .accessibilityLabel("Next set")
            }
            .padding(.horizontal, 6)
        } else {
            // Single set layout: Full-width Complete button
            Button {
                handleComplete()
            } label: {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
            .tint(isCompleted ? .green : .blue)
            .accessibilityLabel(isCompleted ? "Set completed" : "Complete set")
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

#Preview("Multi-set layout") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            Spacer()
            CompactActionBar(
                isCompleted: false,
                currentSetIndex: 1,
                totalSets: 4,
                onComplete: {},
                onPrevious: {},
                onNext: {}
            )
        }
    }
}

#Preview("Single set layout") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            Spacer()
            CompactActionBar(
                isCompleted: false,
                currentSetIndex: 0,
                totalSets: 1,
                onComplete: {},
                onPrevious: {},
                onNext: {}
            )
        }
    }
}

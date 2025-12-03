//
//  CompactSetNavigationBar.swift
//  GymStreakWatch Watch App
//
//  Compact set navigation for space-constrained layouts
//

import SwiftUI
import WatchKit

struct CompactSetNavigationBar: View {
    let currentSetIndex: Int
    let totalSets: Int
    let onPrevious: () -> Void
    let onNext: () -> Void

    private var hasPrevious: Bool {
        currentSetIndex > 0
    }

    private var hasNext: Bool {
        currentSetIndex < totalSets - 1
    }

    var body: some View {
        HStack(spacing: 8) {
            // Previous button (compact)
            Button {
                onPrevious()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
            }
            .buttonStyle(.bordered)
            .disabled(!hasPrevious)
            .opacity(hasPrevious ? 1.0 : 0.3)

            // Progress indicator (minimal)
            VStack(spacing: 2) {
                HStack(spacing: 3) {
                    ForEach(0..<min(totalSets, 5), id: \.self) { index in
                        Circle()
                            .fill(index == currentSetIndex ? Color.blue : Color.gray.opacity(0.3))
                            .frame(width: 4, height: 4)
                    }
                    if totalSets > 5 {
                        Text("...")
                            .font(.system(size: 7))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            // Next button (compact)
            Button {
                onNext()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
            }
            .buttonStyle(.bordered)
            .disabled(!hasNext)
            .opacity(hasNext ? 1.0 : 0.3)
        }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            Spacer()
            CompactSetNavigationBar(
                currentSetIndex: 1,
                totalSets: 4,
                onPrevious: {},
                onNext: {}
            )
        }
    }
}

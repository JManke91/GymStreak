//
//  SetNavigationBar.swift
//  GymStreakWatch Watch App
//
//  Created by Claude Code
//

import SwiftUI
import WatchKit

/// Navigation bar for moving between sets in a full-screen set editor
/// Handles edge cases (first/last set) with disabled states
//struct SetNavigationBar: View {
//    let currentSetIndex: Int
//    let totalSets: Int
//    let onPrevious: () -> Void
//    let onNext: () -> Void
//
//    private var hasPrevious: Bool {
//        currentSetIndex > 0
//    }
//
//    private var hasNext: Bool {
//        currentSetIndex < totalSets - 1
//    }
//
//    var body: some View {
//        HStack(spacing: 0) {
//            // Previous button
//            Button {
//                onPrevious()
//            } label: {
//                HStack(spacing: 4) {
//                    Image(systemName: "chevron.left")
//                        .font(.system(size: 12, weight: .bold))
//                    Text("Prev")
//                        .font(.system(size: 13, weight: .semibold))
//                }
//                .frame(maxWidth: .infinity)
//                .frame(height: 38)
//            }
//            .buttonStyle(.bordered)
//            .disabled(!hasPrevious)
//            .opacity(hasPrevious ? 1.0 : 0.4)
//            .accessibilityLabel("Previous set")
//            .accessibilityHint(hasPrevious ? "Go to set \(currentSetIndex)" : "No previous set")
//
//            Divider()
//                .frame(height: 26)
//                .padding(.horizontal, 6)
//
//            // Next button
//            Button {
//                onNext()
//            } label: {
//                HStack(spacing: 4) {
//                    Text("Next")
//                        .font(.system(size: 13, weight: .semibold))
//                    Image(systemName: "chevron.right")
//                        .font(.system(size: 12, weight: .bold))
//                }
//                .frame(maxWidth: .infinity)
//                .frame(height: 38)
//            }
//            .buttonStyle(.bordered)
//            .disabled(!hasNext)
//            .opacity(hasNext ? 1.0 : 0.4)
//            .accessibilityLabel("Next set")
//            .accessibilityHint(hasNext ? "Go to set \(currentSetIndex + 2)" : "No next set")
//        }
//        .padding(.horizontal, 6)
//        .padding(.bottom, 2)
//        .background(Color.black.opacity(0.001)) // Ensures tappability
//    }
//}

//// MARK: - Preview
//
//#Preview("Middle Set") {
//    ZStack {
//        Color.black.ignoresSafeArea()
//
//        VStack {
//            Spacer()
//            SetNavigationBar(
//                currentSetIndex: 1,
//                totalSets: 4,
//                onPrevious: {},
//                onNext: {}
//            )
//        }
//    }
//}
//
//#Preview("First Set") {
//    ZStack {
//        Color.black.ignoresSafeArea()
//
//        VStack {
//            Spacer()
//            SetNavigationBar(
//                currentSetIndex: 0,
//                totalSets: 4,
//                onPrevious: {},
//                onNext: {}
//            )
//        }
//    }
//}
//
//#Preview("Last Set") {
//    ZStack {
//        Color.black.ignoresSafeArea()
//
//        VStack {
//            Spacer()
//            SetNavigationBar(
//                currentSetIndex: 3,
//                totalSets: 4,
//                onPrevious: {},
//                onNext: {}
//            )
//        }
//    }
//}

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
//            Button {
//                //
//            } label: {
//                Text("press")
//            }
//            .buttonStyle(.plain)

            // Multi-set layout: Prev + Complete + Next
            HStack(spacing: 4) {
                // Previous button
                Button {
                    onPrevious()
                } label: {
                    Image(systemName: "chevron.left")
                        
                }
//                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(!hasPrevious)
                .opacity(hasPrevious ? 1.0 : 0.3)
//                .buttonStyle(.plain)
//                .accessibilityLabel("Previous set")

                Spacer()

                // Complete button
//                HStack(spacing: 0) {
//                    Text("\(currentSetIndex+1)/")
//                        .font(.system(size: 14))
                ZStack {
                    // Put visuals inside the Button label so the entire area responds to taps
                    Button {
                        handleComplete()
                    } label: {
                        ZStack {
                            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 30))

                            // Subtle translucent background when completed to keep visual cue
                            if isCompleted {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 25, height: 25)
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
                        .frame(minWidth: 68, minHeight: 44)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .controlSize(.mini)
                    .buttonStyle(.plain)
                    .accessibilityLabel(isCompleted ? "Set completed. Tap to mark incomplete" : "Complete set")
                }


//                    Text("\(totalSets)")
//                        .font(.system(size: 8))
//                }

//                .tint(isCompleted ? .green : .blue)
//                .accessibilityLabel(isCompleted ? "Set completed" : "Complete set")
//                .frame(height: 50)
//                .background(Color.blue)

                Spacer()

                // Next button
                Button {
                    onNext()
                } label: {
                    Image(systemName: "chevron.right")
                }
//                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(!hasNext)
                .opacity(hasNext ? 1.0 : 0.3)
//                .buttonStyle(.plain)
//                .frame(width: 20, height: 20)
//                .background(Color.red)
//                .accessibilityLabel("Next set")
            }
            .padding(.horizontal, 12)
        } else {
            // Single set layout: Full-width Complete button
            Button {
                handleComplete()
            } label: {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .symbolRenderingMode(.hierarchical)
            }
//            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
            .tint(isCompleted ? .green : .blue)
//            .accessibilityLabel(isCompleted ? "Set completed" : "Complete set")
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

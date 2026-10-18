//
//  WorkoutDetailSupersetGroup.swift
//  GymStreak
//
//  Frames the member blocks of one superset in the workout history detail, in
//  the active workout's superset vocabulary (`SupersetWorkoutGroupView`): the
//  "Superset A (2 exercises)" capsule, the group's colour, a connecting line
//  down the leading edge. Read-only — the round's rest-time control belongs to
//  the live workout, not to a recorded one.
//

import SwiftUI

struct WorkoutDetailSupersetGroup<Content: View>: View {
    let letter: String
    let exerciseCount: Int
    let content: Content

    init(letter: String, exerciseCount: Int, @ViewBuilder content: () -> Content) {
        self.letter = letter
        self.exerciseCount = exerciseCount
        self.content = content()
    }

    private var color: Color {
        SupersetLabelProvider.color(for: letter)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.caption.weight(.semibold))
                Text("superset.label".localized(letter))
                    .font(.caption.weight(.semibold))
                Text("superset.exercise_count".localized(exerciseCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(color.opacity(0.15)))
            .accessibilityElement(children: .combine)

            HStack(alignment: .top, spacing: 0) {
                Rectangle()
                    .fill(color.opacity(0.4))
                    .frame(width: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 1.5))
                    .padding(.leading, 4)

                VStack(spacing: 8) {
                    content
                }
                .padding(.leading, 12)
            }
        }
        .padding(12)
        .background(color.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(color.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

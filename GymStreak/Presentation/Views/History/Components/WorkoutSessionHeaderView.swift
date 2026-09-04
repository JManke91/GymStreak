//
//  WorkoutSessionHeaderView.swift
//  GymStreak
//
//  Editorial header of a recorded session: type chip, weekday + date, routine
//  title. Extracted out of `WorkoutDetailView` so the onboarding history slide
//  shows the shipped header rather than a redrawn copy. Value-driven — the
//  screen formats the date and passes the strings in.
//

import SwiftUI

struct WorkoutSessionHeaderView: View {
    let type: WorkoutType
    let dateText: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                WorkoutTypeChip(type: type)
                Text(dateText)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            Text(title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .kerning(-0.6)
                .foregroundStyle(Color.white)
                .lineLimit(2)
        }
    }
}

#Preview {
    WorkoutSessionHeaderView(type: .push, dateText: "Fr 19. Apr", title: "Oberkörper A")
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.background)
        .preferredColorScheme(.dark)
}

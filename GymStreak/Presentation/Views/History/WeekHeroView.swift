//
//  WeekHeroView.swift
//  GymStreak
//

import SwiftUI

/// "Diese Woche" hero card shown at the top of the Trainings tab.
/// Shows: completed/goal training headline + mini ring, weekday strip, and streak/volume/PRs stats.
struct WeekHeroView: View {
    let weekStats: HistoryStatsService.WeekStats
    let weekDays: [HistoryStatsService.WeekDayStatus]

    private var progress: Double {
        guard weekStats.goal > 0 else { return 0 }
        return min(1.0, Double(weekStats.completedCount) / Double(weekStats.goal))
    }

    private var headlineColor: Color { DesignSystem.Colors.tint }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            dayStrip
            Divider()
                .background(Color.white.opacity(0.06))
            statsRow
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    DesignSystem.Colors.tint.opacity(0.10),
                    DesignSystem.Colors.tint.opacity(0.02),
                    Color.white.opacity(0.02),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(DesignSystem.Colors.tint.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("history.week.this_week".localized.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color.white.opacity(0.5))
                if weekStats.goal > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(weekStats.completedCount)")
                            .foregroundStyle(headlineColor)
                        Text("history.week.trainings_of".localized(weekStats.goal))
                            .foregroundStyle(Color.white.opacity(0.75))
                    }
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .kerning(-0.5)
                } else {
                    // No plan yet: show what was done + invite planning.
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(weekStats.completedCount)")
                            .foregroundStyle(headlineColor)
                        Text("history.week.trainings_done".localized)
                            .foregroundStyle(Color.white.opacity(0.75))
                    }
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .kerning(-0.5)
                    Text("history.week.no_plan".localized)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.tint.opacity(0.9))
                        .padding(.top, 1)
                }
            }
            Spacer()
            ZStack {
                if weekStats.goal > 0 {
                    MiniActivityRing(percent: progress)
                    Image(systemName: "flame.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(DesignSystem.Colors.tint)
                } else {
                    Circle()
                        .stroke(
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [3, 5])
                        )
                        .foregroundStyle(Color.white.opacity(0.18))
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 17))
                        .foregroundStyle(DesignSystem.Colors.tint)
                }
            }
            .frame(width: 52, height: 52)
        }
    }

    // MARK: - Weekday strip

    private var dayStrip: some View {
        HStack(spacing: 6) {
            ForEach(weekDays) { day in
                VStack(spacing: 6) {
                    Text(day.label)
                        .font(.system(size: 10, weight: day.isToday ? .bold : .semibold))
                        .tracking(0.5)
                        .foregroundStyle(
                            day.isToday ? DesignSystem.Colors.tint : Color.white.opacity(0.4)
                        )
                    dayCell(day)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: HistoryStatsService.WeekDayStatus) -> some View {
        ZStack {
            if day.hasWorkout {
                // Completed
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DesignSystem.Colors.tint)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(DesignSystem.Colors.textOnTint)
            } else if day.isPlanned {
                // Planned but not done — dashed outline. Past+missed reads dimmer.
                let missed = !day.isFuture && !day.isToday
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DesignSystem.Colors.tint.opacity(missed ? 0.04 : 0.10))
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5])
                    )
                    .foregroundStyle(DesignSystem.Colors.tint.opacity(missed ? 0.3 : 0.6))
                Circle()
                    .fill(DesignSystem.Colors.tint.opacity(missed ? 0.35 : 0.9))
                    .frame(width: 5, height: 5)
            } else {
                // Rest day
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            }
            if day.isToday {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(DesignSystem.Colors.tint.opacity(0.6), lineWidth: 1.5)
                    .padding(-4)
            }
        }
        .frame(width: 30, height: 30)
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(alignment: .top, spacing: 12) {
            statColumn(
                label: "history.stat.streak".localized,
                value: "\(weekStats.streakWeeks)",
                suffix: "history.stat.streak.unit".localized,
                accent: nil
            )
            Spacer(minLength: 0)
            statColumn(
                label: "history.stat.volume".localized,
                value: formatTons(weekStats.weekVolume),
                suffix: nil,
                accent: weekStats.volumeTrendPct.map { trendLabel($0) }
            )
            Spacer(minLength: 0)
            statColumn(
                label: "history.stat.prs".localized,
                value: "\(weekStats.prCount)",
                suffix: "history.stat.prs.new".localized,
                accent: nil
            )
        }
    }

    private func statColumn(label: String, value: String, suffix: String?, accent: (String, Color)?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.white.opacity(0.4))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                if let suffix {
                    Text(suffix)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
                if let accent {
                    Text(accent.0)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent.1)
                }
            }
        }
    }

    private func formatTons(_ kg: Double) -> String {
        if kg >= 1000 {
            return String(format: "%.1ft", kg / 1000)
        } else {
            return "\(Int(kg))kg"
        }
    }

    private func trendLabel(_ pct: Double) -> (String, Color) {
        let arrow = pct >= 0 ? "↗" : "↘"
        let color: Color = pct >= 0 ? DesignSystem.Colors.tint : Color(red: 1, green: 0.42, blue: 0.42)
        return ("\(arrow) \(Int(abs(pct.rounded())))%", color)
    }
}

#Preview {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()
        WeekHeroView(
            weekStats: .init(
                completedCount: 2,
                goal: 4,
                weekVolume: 12840,
                volumeTrendPct: 8,
                prCount: 4,
                streakWeeks: 12
            ),
            weekDays: (0..<7).map { i in
                let base = Calendar.current.startOfDay(for: Date())
                let date = Calendar.current.date(byAdding: .day, value: i - 2, to: base) ?? base
                return HistoryStatsService.WeekDayStatus(
                    date: date,
                    weekday: i + 1,
                    label: ["Mo","Di","Mi","Do","Fr","Sa","So"][i],
                    isToday: i == 2,
                    isFuture: i > 2,
                    hasWorkout: i == 0 || i == 2,
                    isPlanned: i == 4 || i == 1
                )
            }
        )
        .padding()
    }
    .preferredColorScheme(.dark)
}

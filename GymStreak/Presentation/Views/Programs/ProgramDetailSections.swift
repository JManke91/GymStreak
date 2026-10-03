//
//  ProgramDetailSections.swift
//  GymStreak
//
//  The program detail screen's content cards (design artboard 3): the
//  recovery-time timeline, "How to train it" and "Based on". They only read
//  prebuilt display models. See docs/routine-programs.md.
//

import SwiftUI

/// "Scheduled by recovery time": the explanation, 14 days from today and a legend.
struct ProgramScheduleCard: View {
    let detail: String
    let timeline: [ProgramLibraryViewModel.TimelineDay]
    let legend: [String]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.tint)
                Text("routine_programs.detail.schedule.title".localized)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.white)
            }
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)

            // 14 cells — a bounded literal set, not user-scaled data.
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(timeline) { day in
                    dayCell(day)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { legendItems }
                VStack(alignment: .leading, spacing: 3) { legendItems }
            }
            .font(.system(size: 11))
            .foregroundStyle(Color.white.opacity(0.45))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var legendItems: some View {
        ForEach(legend, id: \.self) { item in
            Text(item).lineLimit(1)
        }
    }

    private func dayCell(_ day: ProgramLibraryViewModel.TimelineDay) -> some View {
        VStack(spacing: 4) {
            Text(day.weekday)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(day.isToday ? DesignSystem.Colors.tint : Color.white.opacity(0.4))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(day.label == nil ? Color.white.opacity(0.04) : DesignSystem.Colors.tint.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(day.isToday ? DesignSystem.Colors.tint : .clear, lineWidth: 1.5)
                )
                .overlay {
                    if let label = day.label {
                        Text(label)
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(DesignSystem.Colors.tint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
        }
        .accessibilityElement(children: .combine)
    }
}

/// "How to train it": numbered rules. A rule that points to another program
/// (Full Body's graduation → Push / Pull / Legs) links to its detail.
struct ProgramGuidanceCard<Destination: View>: View {
    let rules: [ProgramLibraryViewModel.GuidanceRule]
    @ViewBuilder let destination: (_ programId: String) -> Destination

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rules) { rule in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        Text(rule.number)
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(DesignSystem.Colors.tint)
                            .frame(width: 28, height: 28)
                            .background(DesignSystem.Colors.tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(rule.title)
                                .font(.system(size: 14, weight: .heavy))
                                .foregroundStyle(.white)
                            Text(rule.detail)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Color.white.opacity(0.6))
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)

                    if let link = rule.link {
                        NavigationLink {
                            destination(link.programId)
                        } label: {
                            HStack(spacing: 4) {
                                Text(link.title)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(DesignSystem.Colors.tint)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 40)
                    }
                }
                .padding(.vertical, 13)
                .overlay(alignment: .bottom) {
                    if rule.id != rules.last?.id {
                        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(DesignSystem.Colors.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// "Based on": each source with its one-line role.
struct ProgramSourcesCard: View {
    let sources: [ProgramLibraryViewModel.SourceLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(sources) { source in
                Text("\(Text(source.name).bold().foregroundStyle(.white)) · \(source.role)")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

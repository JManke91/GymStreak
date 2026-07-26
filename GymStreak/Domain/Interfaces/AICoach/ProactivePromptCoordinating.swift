//
//  ProactivePromptCoordinating.swift
//  GymStreak
//

import Foundation

/// State and actions used by History's proactive monthly recap card.
///
/// Presentation depends on this boundary; the concrete persistence/availability-aware
/// coordinator is supplied by the composition root.
@MainActor
protocol ProactivePromptCoordinating: AnyObject {
    var shouldShow: Bool { get }
    var monthLabel: String { get }
    var sessionCount: Int { get }
    var totalVolumeTons: Double { get }
    var newPRCount: Int { get }

    func evaluate(lastMonth: HistorySnapshot.LastMonthStats)
    func dismiss()
}

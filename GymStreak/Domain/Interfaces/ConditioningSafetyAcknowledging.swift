//
//  ConditioningSafetyAcknowledging.swift
//  GymStreak
//
//  Whether the conditioning safety screen was acknowledged — it must be once
//  before the first session. See docs/fight-conditioning.md.
//

import Foundation

@MainActor
protocol ConditioningSafetyAcknowledging: AnyObject {
    var hasAcknowledgedSafety: Bool { get }
    func recordSafetyAcknowledged()
}

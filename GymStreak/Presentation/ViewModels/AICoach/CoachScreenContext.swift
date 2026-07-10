//
//  CoachScreenContext.swift
//  GymStreak
//
//  Lightweight UI-level record of the entity the user is currently looking at,
//  so the globally reachable coach chat can pre-seed one screen-relevant
//  suggestion chip ("What's my PR on Bench Press?").
//
//  Views with a single clear anchor entity set `anchor` in onAppear/onChange
//  and clear it in onDisappear. This is a plain UI pre-fill (a name string) —
//  the model never reads the screen; the pre-seeded question is grounded by
//  the same chat tools as any typed question.
//  See docs/ai-coach-entry-point-concepts.md.
//

import Foundation
import Observation

@Observable
@MainActor
final class CoachScreenContext {

    static let shared = CoachScreenContext()
    private init() {}

    enum Anchor: Equatable {
        case exercise(name: String)
    }

    /// The current screen's anchor entity, or `nil` on screens without one.
    var anchor: Anchor?

    /// Snapshot of `anchor` frozen at the moment the coach bar is tapped.
    ///
    /// Presenting the chat's fullScreenCover fires `onDisappear` on the covered
    /// screen — which clears `anchor` — in an order SwiftUI doesn't guarantee
    /// relative to the chat's `onAppear`. The chat therefore reads this frozen
    /// copy, captured synchronously in the bar's tap action.
    private(set) var presentedAnchor: Anchor?

    /// Called from the coach bar's tap action, before presentation starts.
    func freezeForPresentation() {
        presentedAnchor = anchor
    }
}

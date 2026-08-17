//
//  CustomerCenterEventTests.swift
//  GymStreakTests
//
//  That every Customer Center event the SDK reports becomes a distinct, legible
//  log line (docs/pro-subscription.md §5j).
//
//  The Customer Center is a screen this app does not draw: restores,
//  cancellations, refund requests and survey answers all happen inside it. The
//  log is the only record that they happened at all, so an event whose message
//  is empty, or indistinguishable from another event's, is a support question
//  that cannot be answered.
//

import Foundation
import Testing
@testable import GymStreak

@Suite
@MainActor
struct CustomerCenterEventTests {

    private static let allEvents: [CustomerCenterEvent] = [
        .restoreStarted,
        .restoreCompleted,
        .restoreFailed("network unreachable"),
        .showingManageSubscriptions,
        .refundRequestStarted(productID: "yearly"),
        .refundRequestCompleted(productID: "yearly", status: "success"),
        .feedbackSurveyCompleted(optionID: "too_expensive"),
        .managementOptionSelected("Cancel")
    ]

    @Test("Every event produces a distinct, non-empty message")
    func messagesAreDistinct() {
        let messages = Self.allEvents.map(\.message)

        #expect(messages.allSatisfy { !$0.isEmpty })
        #expect(Set(messages).count == messages.count)
    }

    /// The payloads are the whole point: "a refund request completed" without
    /// the product and the outcome answers nothing.
    @Test("The payloads survive into the message")
    func payloadsAreCarried() {
        #expect(CustomerCenterEvent.restoreFailed("boom").message.contains("boom"))
        #expect(
            CustomerCenterEvent
                .refundRequestStarted(productID: "lifetime")
                .message
                .contains("lifetime")
        )

        let completed = CustomerCenterEvent
            .refundRequestCompleted(productID: "monthly", status: "userCancelled")
            .message
        #expect(completed.contains("monthly"))
        #expect(completed.contains("userCancelled"))

        #expect(
            CustomerCenterEvent
                .feedbackSurveyCompleted(optionID: "not_using")
                .message
                .contains("not_using")
        )
        #expect(
            CustomerCenterEvent
                .managementOptionSelected("MissingPurchase")
                .message
                .contains("MissingPurchase")
        )
    }

    /// Logging must never be the thing that crashes the Customer Center.
    @Test("Logging every event is harmless")
    func loggingIsSafe() {
        for event in Self.allEvents {
            event.log()
        }
    }
}

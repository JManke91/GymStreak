//
//  AICoachTelemetry.swift
//  GymStreak
//
//  Lightweight telemetry helper for the AI Coach service layer.
//  Uses os.Logger only — no third-party analytics, no user data.
//

import Foundation
import os

/// Lightweight telemetry helper for AI Coach generations.
///
/// Logs structured events via `os.Logger` so they appear in Console.app
/// and Instruments. Never logs prompt text, narrative content, or any
/// personally identifiable workout data.
@MainActor
enum AICoachTelemetry {

    static let logger = Logger(subsystem: "app.gymstreak.aicoach", category: "Telemetry")

    /// Records a completed (or failed) generation attempt.
    ///
    /// - Parameters:
    ///   - useCase: Identifier string, e.g. `"post_workout"`, `"period_recap"`.
    ///   - durationMs: Wall-clock time from session creation to stream exhaustion.
    ///   - inputTokens: Estimated input token count, or `nil` if unavailable.
    ///   - outputTokens: Estimated output token count, or `nil` if unavailable.
    ///   - success: Whether the stream completed without throwing.
    static func recordGeneration(
        useCase: String,
        durationMs: Int,
        inputTokens: Int?,
        outputTokens: Int?,
        success: Bool
    ) {
        logger.info(
            "ai_coach.generation useCase=\(useCase, privacy: .public) duration_ms=\(durationMs) input_tokens=\(inputTokens ?? -1) output_tokens=\(outputTokens ?? -1) success=\(success, privacy: .public)"
        )
    }

    /// Records an error that prevented generation from completing.
    ///
    /// - Parameters:
    ///   - useCase: Identifier string for the coach surface.
    ///   - errorTypeName: `String(describing: type(of: error))` — type only, no content.
    static func recordError(useCase: String, errorTypeName: String) {
        logger.warning(
            "ai_coach.error useCase=\(useCase, privacy: .public) type=\(errorTypeName, privacy: .public)"
        )
    }
}

//
//  ConditioningCueDeliverer.swift
//  GymStreak
//
//  Sound + haptic for conditioning transitions while the runner is on screen,
//  and one local notification per upcoming transition for while it is not.
//  The app installs no `UNUserNotificationCenterDelegate`, so a notification
//  that fires while GymStreak is in the foreground is not presented — the
//  in-app cue is the only one heard then. See docs/fight-conditioning.md.
//

import AudioToolbox
import Foundation
import UIKit
import UserNotifications

@MainActor
final class ConditioningCueDeliverer: ConditioningCueDelivering {
    private static let identifierPrefix = "conditioning.cue."
    /// iOS keeps at most 64 pending requests per app, shared with the rest
    /// timer and workout reminders. The longest session has ~35 transitions.
    private static let maxPendingCues = 48

    private let center: UNUserNotificationCenter
    private var scheduledIdentifiers: [String] = []
    private var generation = 0

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    // MARK: - Foreground

    func play(_ cue: ConditioningLiveCue) {
        switch cue {
        case .leadIn:
            AudioServicesPlaySystemSound(1057) // "Tink"
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .effortStart:
            AudioServicesPlaySystemSound(1113) // "begin record"
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .recoveryStart:
            AudioServicesPlaySystemSound(1114) // "end record"
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .finished:
            AudioServicesPlaySystemSound(1025) // "fanfare"
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    // MARK: - Background

    @discardableResult
    func scheduleBackgroundCues(_ cues: [ConditioningScheduledCue]) async -> Bool {
        cancelBackgroundCues()
        generation += 1
        let scheduledGeneration = generation

        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            status = granted ? .authorized : .denied
        }
        guard status == .authorized else { return false }

        // Requests a previous app process left behind (it was killed mid-session).
        let stale = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) }
        guard generation == scheduledGeneration else { return true }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        var added: [String] = []
        for (offset, cue) in cues.prefix(Self.maxPendingCues).enumerated() {
            // A pause or end during the permission prompt or a prior `add`
            // supersedes this batch.
            guard generation == scheduledGeneration else { break }
            let interval = cue.fireDate.timeIntervalSinceNow
            guard interval > 0 else { continue }

            let content = UNMutableNotificationContent()
            content.title = cue.title
            content.body = cue.body
            content.sound = .default

            let identifier = Self.identifierPrefix + "\(scheduledGeneration).\(offset)"
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            )
            do {
                try await center.add(request)
                added.append(identifier)
            } catch {
                print("Conditioning cue scheduling failed: \(error)")
            }
        }
        if generation == scheduledGeneration {
            scheduledIdentifiers.append(contentsOf: added)
        } else {
            // Superseded mid-flight: remove only this batch's requests, never a
            // newer batch's.
            center.removePendingNotificationRequests(withIdentifiers: added)
        }
        return true
    }

    func cancelBackgroundCues() {
        generation += 1
        guard !scheduledIdentifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: scheduledIdentifiers)
        center.removeDeliveredNotifications(withIdentifiers: scheduledIdentifiers)
        scheduledIdentifiers.removeAll()
    }
}

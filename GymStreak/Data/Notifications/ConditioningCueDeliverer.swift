//
//  ConditioningCueDeliverer.swift
//  GymStreak
//
//  Sound + haptic for conditioning transitions while the runner is on screen,
//  and one local notification per upcoming transition for while it is not.
//  The app installs no `UNUserNotificationCenterDelegate`, so a notification
//  that fires while GymStreak is in the foreground is not presented — the
//  in-app cue is the only one heard then. The round timer's cues ring its
//  bell (`RoundTimerBell`) instead of a system sound, and its notifications
//  carry the same bell files. See docs/fight-conditioning.md.
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
    private let bell: RoundTimerBell
    private var scheduledIdentifiers: [String] = []
    private var generation = 0

    init(center: UNUserNotificationCenter = .current(), bell: RoundTimerBell = RoundTimerBell()) {
        self.center = center
        self.bell = bell
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
        case .roundStart:
            bell.play(.start)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .roundWarning:
            bell.play(.warning)
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .roundEnd:
            bell.play(.end)
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .roundTimerFinished:
            bell.play(.finished)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    func prepareRoundTimer() {
        bell.prepare()
    }

    /// The round timer's notifications ring its bell; everything else keeps
    /// the default sound.
    private static func sound(for cue: ConditioningLiveCue?) -> UNNotificationSound {
        let bell: RoundTimerBell.Sound? = switch cue {
        case .roundStart: .start
        case .roundWarning: .warning
        case .roundEnd: .end
        case .roundTimerFinished: .finished
        default: nil
        }
        guard let bell else { return .default }
        return UNNotificationSound(named: UNNotificationSoundName(bell.fileName))
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
            content.sound = Self.sound(for: cue.cue)

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

//
//  ConditioningAddOnViewModel.swift
//  GymStreak
//
//  The post-workout conditioning add-on: after a strength workout on iPhone,
//  offer today's program session — now if it is easy aerobic work, later if it
//  is hard. See docs/fight-conditioning.md (ticket 05).
//

import Foundation
import Observation

@Observable
@MainActor
final class ConditioningAddOnViewModel {

    /// What the workout summary offers, if anything. `.none` is also what a
    /// dismissal leaves behind, so the section simply stops rendering.
    private(set) var offer: ConditioningAddOnOffer = .none

    /// When the reminder the user asked for will fire. Non-`nil` replaces the
    /// buttons with a confirmation, so the card never asks twice.
    private(set) var remindedAt: Date?

    /// The user asked to be reminded but notifications are not granted. Shown
    /// instead of a confirmation that would be a lie.
    private(set) var isReminderUnavailable = false

    /// The running session. Settable because the app root binds it to a
    /// `fullScreenCover(item:)`, which writes `nil` back on dismissal — the same
    /// shape `ConditioningLibraryViewModel.activeRun` has.
    ///
    /// It lives on this app-lifetime view model, not on the summary screen,
    /// because the offer is made on a sheet that dismisses itself before the
    /// session starts: a runner owned there would be torn down with it.
    var activeRun: ConditioningRunViewModel?

    private(set) var needsSafetyAcknowledgement = false

    @ObservationIgnored private let program: ConditioningProgramViewModel
    @ObservationIgnored private let safety: any ConditioningSafetyAcknowledging
    @ObservationIgnored private let reminders: any ConditioningReminderScheduling
    @ObservationIgnored private let permission: any WorkoutReminderPermissionRequesting
    @ObservationIgnored private let makeRun: @MainActor (ConditioningSessionPlan) -> ConditioningRunViewModel
    @ObservationIgnored private let calendar: Calendar

    init(
        program: ConditioningProgramViewModel,
        safety: any ConditioningSafetyAcknowledging,
        reminders: any ConditioningReminderScheduling,
        permission: any WorkoutReminderPermissionRequesting,
        makeRun: @escaping @MainActor (ConditioningSessionPlan) -> ConditioningRunViewModel,
        calendar: Calendar = .current
    ) {
        self.program = program
        self.safety = safety
        self.reminders = reminders
        self.permission = permission
        self.makeRun = makeRun
        self.calendar = calendar
    }

    // MARK: - The offer

    /// Computes the offer for a strength workout that has just ended.
    ///
    /// Synchronous and bounded — two small repository reads, the same ones the
    /// program dashboard already makes — so the summary screen can call it as it
    /// appears without the save waiting on anything.
    func prepare(finishedAt: Date, isHeavyLowerBody: Bool) {
        remindedAt = nil
        isReminderUnavailable = false
        offer = program.addOn(finishedAt: finishedAt, isHeavyLowerBody: isHeavyLowerBody)
    }

    /// What the workout summary calls: the just-finished session is read and
    /// classified **here**, not in the view (Hard rule 3), and through the same
    /// helper the program dashboard uses for committed workouts, so the two can
    /// never disagree about what counts as a leg day.
    ///
    /// `endTime` is stamped by `pauseForCompletion()` when the user taps Finish,
    /// so it is when the lifting actually stopped — not when they got around to
    /// tapping Save.
    func prepare(for session: WorkoutSession) {
        let entry = ConditioningProgramViewModel.strengthEntry(
            session,
            endTime: session.endTime ?? Date()
        )
        prepare(finishedAt: entry.endTime, isHeavyLowerBody: entry.isHeavyLowerBody)
    }

    /// One tap, and the offer is gone for this workout. Nothing is persisted:
    /// the next workout asks again, because by then the answer may differ.
    func dismiss() {
        offer = .none
    }

    // MARK: - Actions

    /// Schedules the reminder for the hard session, at the first waking hour on
    /// or after the six-hour mark.
    func remindLater() async {
        guard case .later(let target, let notBefore) = offer else { return }
        let fireDate = ConditioningProgramCoach.reminderFireDate(notBefore: notBefore, calendar: calendar)

        // The user just asked for a notification, which makes this the one
        // moment in the app where raising the system prompt is exactly what
        // they requested. It is still asked through the same Domain gateway the
        // reminder offer uses, so nothing here reaches `UNUserNotificationCenter`.
        if await permission.isReminderPermissionUndetermined() {
            await permission.requestReminderPermission()
        }

        let scheduled = await reminders.scheduleConditioningReminder(
            title: ConditioningProgramCopy.addOnReminderTitle,
            body: ConditioningProgramCopy.addOnReminderBody(target),
            at: fireDate
        )
        if scheduled {
            remindedAt = fireDate
        } else {
            isReminderUnavailable = true
        }
    }

    /// Starts the offered session. For a `.later` offer this is the explicit
    /// override — the card says why it is a worse idea and lets the user do it
    /// anyway, because the app does not know what else is in their day.
    ///
    /// Goes straight to the runner rather than via `ConditioningPreviewView`:
    /// the volume comes from the program target and the modality from the
    /// session's own default, which is what the preview would have opened on.
    /// To restore the choice, route this to the preview with
    /// `initialOptions: target.options` instead.
    func start() {
        guard let target = offer.target else { return }
        // A pending reminder for a session that is starting now is noise.
        reminders.cancelConditioningReminder()
        let plan = ConditioningSessionPlan(
            definition: target.definition,
            options: target.options,
            modality: target.definition.modalities.first ?? .run
        )
        needsSafetyAcknowledgement = !safety.hasAcknowledgedSafety
        offer = .none
        activeRun = makeRun(plan)
    }

    func acknowledgeSafety() {
        safety.recordSafetyAcknowledged()
        needsSafetyAcknowledgement = false
    }

    /// The finished session counts toward the week, so the program dashboard and
    /// the Routines card have to be rebuilt before either is looked at again.
    func runDidFinish() {
        program.refresh()
    }
}

extension ConditioningAddOnOffer {
    /// The session either branch is about; `nil` when there is no offer.
    var target: ConditioningProgramTarget? {
        switch self {
        case .startNow(let target): target
        case .later(let target, _): target
        case .none: nil
        }
    }
}

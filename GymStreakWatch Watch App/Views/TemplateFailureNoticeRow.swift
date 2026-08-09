//
//  TemplateFailureNoticeRow.swift
//  GymStreakWatch Watch App
//
//  Tells the user that a routine change they accepted on this watch was never
//  applied — the one failure the history/template split (ADR 0001) made silent:
//  the workout still reaches the iPhone, the routine update does not, and the
//  optimistic value simply reverts.
//
//  It sits on the routine list because that is the screen the user opens before
//  every workout, and it stays there until dismissed: a reverted weight is
//  exactly the kind of thing that is otherwise discovered a week later.
//

import SwiftUI

struct TemplateFailureNoticeRow: View {
    let notice: WatchTemplateFailureNotice
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OnyxWatch.Spacing.sm) {
            HStack(spacing: OnyxWatch.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.watchCaption)
                    .foregroundStyle(OnyxWatch.Colors.warning)

                Text(notice.routineName ?? String(localized: "Routine"))
                    .font(.watchSubheadline)
                    .lineLimit(2)
            }

            Text(message)
                .font(.watchCaption2)
                .foregroundStyle(OnyxWatch.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onDismiss) {
                Text("Got It")
                    .font(.watchCaption)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, OnyxWatch.Spacing.xs)
    }

    /// The acknowledgment carries no human-readable reason, so each coarse
    /// reason maps to one sentence that says what happened and what to do.
    private var message: LocalizedStringKey {
        switch notice.reason {
        case .routineChangedOnPhone:
            return "Your change wasn't applied — this routine had already changed on your iPhone. Adjust it there."
        case .routineDeleted:
            return "Your change wasn't applied — this routine no longer exists on your iPhone."
        case .couldNotSend:
            return "Your change couldn't be sent to your iPhone. Adjust the routine there."
        }
    }
}

#Preview {
    List {
        TemplateFailureNoticeRow(
            notice: WatchTemplateFailureNotice(
                routineID: UUID(), routineName: "Push Day", reason: .routineChangedOnPhone
            ),
            onDismiss: {}
        )
    }
}

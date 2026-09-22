//
//  ConditioningSessionDetailView.swift
//  GymStreakWatch Watch App
//
//  One offered session before it starts: volume, total time, the personal
//  heart-rate range, the machine, a stop-rule line, and Start
//  (ticket 06, docs/fight-conditioning.md).
//

import SwiftUI

struct ConditioningSessionDetailView: View {
    let session: WatchConditioningSession

    @Environment(WatchConditioningRunViewModel.self) private var run
    @State private var modality: String
    private let totalDuration: TimeInterval

    init(session: WatchConditioningSession) {
        self.session = session
        _modality = State(initialValue: session.modalities.first ?? "")
        totalDuration = ConditioningTimeline(phases: session.phases).totalDuration
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Volume", value: WatchConditioningCopy.volume(session))
                LabeledContent("Total", value: WatchConditioningCopy.clock(totalDuration))
                if let zone = session.heartRateZone {
                    LabeledContent("Target", value: WatchConditioningCopy.zone(zone))
                }
            }

            if session.modalities.count > 1 {
                Picker("Machine", selection: $modality) {
                    ForEach(session.modalities, id: \.self) { raw in
                        Label(WatchConditioningCopy.modality(raw), systemImage: WatchConditioningCopy.modalitySymbol(raw))
                            .tag(raw)
                    }
                }
            }

            Button {
                Task { await run.start(session, modality: modality) }
            } label: {
                Label("Start", systemImage: "play.fill")
                    .font(.watchSubheadline)
                    .foregroundStyle(OnyxWatch.Colors.textOnTint)
                    .frame(maxWidth: .infinity)
            }
            .listRowBackground(
                RoundedRectangle(cornerRadius: OnyxWatch.Dimensions.cornerRadiusLG)
                    .fill(OnyxWatch.Colors.tint)
            )

            Text("Stop on chest pain, dizziness or unusual breathlessness.")
                .font(.watchCaption2)
                .foregroundStyle(OnyxWatch.Colors.textSecondary)
                .listRowBackground(Color.clear)
        }
        .navigationTitle(WatchConditioningCopy.title(session.sessionType))
    }
}

//
//  MatSessionSportPickerView.swift
//  GymStreakWatch Watch App
//
//  The watch's mat-session entry (positioning ticket 05,
//  docs/fight-conditioning.md): the row on the routine list, and the sport
//  list it opens — tapping a sport starts the recording.
//

import SwiftUI

struct MatSessionDestination: Hashable {}

/// The row on the routine list. Always offered: recording sparring needs no
/// program and no synced data.
struct MatSessionEntryRow: View {
    var body: some View {
        NavigationLink(value: MatSessionDestination()) {
            VStack(alignment: .leading, spacing: 2) {
                Label("Mat session", systemImage: "figure.martial.arts")
                    .font(.headline)
                Text("BJJ, sparring, pads")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

struct MatSessionSportPickerView: View {
    @Environment(WatchMatSessionViewModel.self) private var mat

    var body: some View {
        List {
            ForEach(WatchMatSport.allCases) { sport in
                Button {
                    Task { await mat.start(sport) }
                } label: {
                    Label(WatchMatSessionCopy.sport(sport), systemImage: WatchMatSessionCopy.symbol(sport))
                        .font(.headline)
                }
            }
        }
        .navigationTitle("Mat session")
    }
}

//
//  ConditioningSessionListView.swift
//  GymStreakWatch Watch App
//
//  The watch's conditioning entry (ticket 06, docs/fight-conditioning.md): the
//  row on the routine list, and the list of this program week's open sessions
//  it opens. Nothing renders without a synced program — no dead end, no paywall.
//

import SwiftUI

struct ConditioningDestination: Hashable {}

struct ConditioningSessionDestination: Hashable {
    let sessionType: String
}

/// The row on the routine list; the caller shows it only when sessions are offered.
struct ConditioningEntryRow: View {
    let today: WatchConditioningSession?
    let sessionCount: Int

    var body: some View {
        NavigationLink(value: ConditioningDestination()) {
            VStack(alignment: .leading, spacing: 2) {
                Label("Conditioning", systemImage: "figure.boxing")
                    .font(.headline)
                Group {
                    if let today {
                        Text("Today: \(WatchConditioningCopy.title(today.sessionType))")
                    } else {
                        Text("\(sessionCount) sessions this week")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
        }
    }
}

struct ConditioningSessionListView: View {
    @Environment(WatchConditioningStore.self) private var store

    var body: some View {
        List {
            if let today = store.today {
                Section("Today") { row(today) }
            }
            if !store.others.isEmpty {
                Section("This week") {
                    ForEach(store.others) { row($0) }
                }
            }
        }
        .navigationTitle("Conditioning")
        .navigationDestination(for: ConditioningSessionDestination.self) { destination in
            // Resolved by identity at push time, like the routine detail.
            if let session = store.sessions.first(where: { $0.sessionType == destination.sessionType }) {
                ConditioningSessionDetailView(session: session)
            }
        }
        .overlay {
            if store.sessions.isEmpty {
                // The week rolled over while this screen was open.
                ContentUnavailableView("No sessions", systemImage: "figure.boxing")
            }
        }
    }

    private func row(_ session: WatchConditioningSession) -> some View {
        NavigationLink(value: ConditioningSessionDestination(sessionType: session.sessionType)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(WatchConditioningCopy.title(session.sessionType))
                    .font(.headline)
                Text(WatchConditioningCopy.volume(session))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

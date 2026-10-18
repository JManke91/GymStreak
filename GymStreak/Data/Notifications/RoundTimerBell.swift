//
//  RoundTimerBell.swift
//  GymStreak
//
//  The round timer's sounds while the app is on screen: a bell for round
//  start and end, a clacker for the warning, three bells when the rounds are
//  over. Played through an `AVAudioSession` in the playback category, so the
//  bell rings with the ring/silent switch on silent — a phone on a gym floor
//  usually is — and ducks the music playing from this phone for its duration.
//  The files are also what the lock-screen notifications play; they are
//  synthesized once (docs/fight-conditioning.md, "Round timer").
//

import AVFoundation
import Foundation

@MainActor
final class RoundTimerBell {

    enum Sound: String, CaseIterable {
        case start = "round-timer-start"
        case warning = "round-timer-warning"
        case end = "round-timer-end"
        case finished = "round-timer-finished"

        /// The bundled file, as `UNNotificationSound(named:)` wants it.
        var fileName: String { rawValue + ".caf" }
    }

    private var players: [Sound: AVAudioPlayer] = [:]
    private var deactivation: Task<Void, Never>?
    private var isCategorySet = false

    /// Called when a run is set up, before the opening bell: sets the category
    /// once and loads the four players, so the first ring pays only `setActive`.
    /// Not done at launch — nothing else in the app plays audio.
    func prepare() {
        setCategoryIfNeeded()
        for sound in Sound.allCases { _ = player(for: sound) }
    }

    func play(_ sound: Sound) {
        guard let player = player(for: sound) else { return }
        setCategoryIfNeeded()
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Round timer audio session failed: \(error)")
        }
        player.currentTime = 0
        player.play()

        // Hand the music its volume back once the bell has rung out.
        deactivation?.cancel()
        let silenceAfter = player.duration + 0.3
        deactivation = Task {
            try? await Task.sleep(for: .seconds(silenceAfter))
            guard !Task.isCancelled else { return }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func setCategoryIfNeeded() {
        guard !isCategorySet else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers, .duckOthers])
            isCategorySet = true
        } catch {
            print("Round timer audio category failed: \(error)")
        }
    }

    private func player(for sound: Sound) -> AVAudioPlayer? {
        if let player = players[sound] { return player }
        guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "caf"),
              let player = try? AVAudioPlayer(contentsOf: url)
        else {
            print("Round timer sound missing: \(sound.fileName)")
            return nil
        }
        player.prepareToPlay()
        players[sound] = player
        return player
    }
}

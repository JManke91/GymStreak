//
//  ShareCardPreviewing.swift
//  GymStreak
//
//  What the share preview sheet needs from a card's view model, whichever card it is
//  (strength or conditioning), and the Save-to-Photos flow they share.
//  See docs/workout-sharing.md.
//

import UIKit

/// The preview's "Save" button.
enum ShareSaveState: Equatable {
    case idle, saving, saved
}

@MainActor
protocol ShareCardPreviewing: AnyObject, Observable {
    associatedtype Card: Equatable

    /// The card as it renders now; nil hides it.
    var card: Card? { get }
    /// Written only by `saveImage()` and by a layer change (`cardDidChange()`).
    var saveState: ShareSaveState { get set }
    /// Set when a save was refused; the sheet shows it as an alert.
    var saveError: PhotoSaveError? { get set }
    /// The line that travels with the image: the wordmark and the attributable App Store link.
    var shareMessage: String { get }
    var photoLibrary: PhotoLibrarySaving { get }

    /// The card at its full 1080 × 1920 pixels. Called from a button, never from a body.
    func renderImage() -> UIImage?
}

extension ShareCardPreviewing {

    /// Renders the card and saves it straight to Photos, for posting a story from another app
    /// without going through the share sheet. The image carries the wordmark but not the link.
    func saveImage() async {
        guard saveState != .saving, let data = renderImage()?.pngData() else { return }
        let savedCard = card
        saveState = .saving
        do {
            try await photoLibrary.savePNG(data)
            // A chip changed mid-save: the image in Photos is not the card on screen.
            saveState = card == savedCard ? .saved : .idle
        } catch {
            saveState = .idle
            saveError = error as? PhotoSaveError ?? .failed
        }
    }

    /// A changed card is no longer the one that was saved. Not while saving: that would
    /// re-enable the button mid-save; `saveImage` settles that case itself.
    func cardDidChange() {
        if saveState == .saved { saveState = .idle }
    }

    /// The share line for a link campaign (`SupportLinks.Campaign`).
    static func shareMessage(campaign: String) -> String {
        "share.message".localized(
            AppBrand.wordmark,
            SupportLinks.appStoreCampaignLink(campaign: campaign).absoluteString
        )
    }
}

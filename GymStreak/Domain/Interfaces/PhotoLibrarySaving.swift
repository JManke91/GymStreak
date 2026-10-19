//
//  PhotoLibrarySaving.swift
//  GymStreak
//
//  The share preview's "Save image" path into Photos. See docs/workout-sharing.md.
//

import Foundation

/// Saves an image the user asked to keep into their photo library, asking for add-only
/// access the first time. PNG bytes in, so no UIKit or Photos type crosses into Domain.
protocol PhotoLibrarySaving: Sendable {
    func savePNG(_ data: Data) async throws
}

/// Why a save did not happen, as much as the UI needs to choose its message.
enum PhotoSaveError: Error {
    /// The user refused access. Only Settings can undo that.
    case denied
    /// Parental controls or device management forbid it; the user can't grant it.
    case restricted
    case failed
}

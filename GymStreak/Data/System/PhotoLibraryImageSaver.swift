//
//  PhotoLibraryImageSaver.swift
//  GymStreak
//
//  `PhotoLibrarySaving` over PhotoKit's add-only access. See docs/workout-sharing.md.
//

import Foundation
import Photos

struct PhotoLibraryImageSaver: PhotoLibrarySaving {

    func savePNG(_ data: Data) async throws {
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        switch status {
        // `.limited` describes read access and isn't expected for add-only; it can still save.
        case .authorized, .limited: break
        case .denied: throw PhotoSaveError.denied
        case .restricted: throw PhotoSaveError.restricted
        default: throw PhotoSaveError.failed
        }
        do {
            try await Self.addPhoto(data)
        } catch {
            throw PhotoSaveError.failed
        }
    }

    /// Photos runs the change block on an arbitrary serial queue and does not annotate it
    /// `NS_SWIFT_SENDABLE`. `@Sendable` keeps it from being inferred main-actor-isolated,
    /// which would trap off-main at runtime (docs/swift6-concurrency.md §4a).
    private nonisolated static func addPhoto(_ data: Data) async throws {
        try await PHPhotoLibrary.shared().performChanges { @Sendable in
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
        }
    }
}

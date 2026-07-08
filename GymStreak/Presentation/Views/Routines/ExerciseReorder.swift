//
//  ExerciseReorder.swift
//  GymStreak
//
//  Drag-to-reorder for exercise cards in RoutineDetailView's edit mode.
//  RoutineDetailView moved off `List` (whose intra-row height changes snap
//  instead of animating) to `ScrollView` + `LazyVStack` for fluid card/set
//  expansion; this reimplements the reordering that `List.onMove` provided.
//
//  Uses system drag & drop (`.onDrag` + `.onDrop`) so drag-lift and
//  auto-scroll-near-edges come for free inside the ScrollView. Reordering
//  happens live as the dragged card hovers over a sibling.
//

import SwiftUI
import UniformTypeIdentifiers

/// Live reorder delegate: as the dragged exercise hovers over `item`, the two
/// swap position in the working order and the change is persisted immediately.
struct ExerciseDropDelegate: DropDelegate {
    let item: RoutineExercise
    /// Current sorted order of exercises (by `order`).
    let exercises: [RoutineExercise]
    @Binding var draggingId: UUID?
    /// Persists a new order (reassigns `order` + saves).
    let onReorder: ([RoutineExercise]) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingId,
              draggingId != item.id,
              let from = exercises.firstIndex(where: { $0.id == draggingId }),
              let to = exercises.firstIndex(where: { $0.id == item.id })
        else { return }

        var updated = exercises
        let moved = updated.remove(at: from)
        updated.insert(moved, at: to)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(DesignSystem.Animation.spring) {
            onReorder(updated)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingId = nil
        return true
    }
}

extension View {
    /// Makes an edit-mode exercise card a drag source and a live drop target.
    @ViewBuilder
    func exerciseReorderable(
        _ routineExercise: RoutineExercise,
        exercises: [RoutineExercise],
        draggingId: Binding<UUID?>,
        onReorder: @escaping ([RoutineExercise]) -> Void
    ) -> some View {
        self
            .opacity(draggingId.wrappedValue == routineExercise.id ? 0.5 : 1.0)
            .onDrag {
                draggingId.wrappedValue = routineExercise.id
                return NSItemProvider(object: routineExercise.id.uuidString as NSString)
            }
            .onDrop(
                of: [UTType.text],
                delegate: ExerciseDropDelegate(
                    item: routineExercise,
                    exercises: exercises,
                    draggingId: draggingId,
                    onReorder: onReorder
                )
            )
    }
}

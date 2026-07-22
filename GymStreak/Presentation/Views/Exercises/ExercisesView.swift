import SwiftUI
import SwiftData

struct ExercisesView: View {
    @EnvironmentObject private var dependencies: AppDependencies

    var body: some View {
        ExercisesViewInternal(dependencies: dependencies)
    }
}

private struct ExercisesViewInternal: View {
    @StateObject private var viewModel: ExercisesViewModel
    @State private var searchText = ""
    @State private var selectedCategoryKey: String? = nil
    @State private var selectedEquipment: EquipmentType? = nil
    @FocusState private var isSearchFocused: Bool

    init(dependencies: AppDependencies) {
        self._viewModel = StateObject(wrappedValue: ExercisesViewModel(
            exerciseRepository: dependencies.exerciseRepository,
            routineRepository: dependencies.routineRepository,
            catalogSync: dependencies.exerciseCatalogSync
        ))
    }

    // MARK: - Derived state (filtering/grouping lives in the ViewModel)

    private var filteredSections: [ExerciseSection] {
        viewModel.sections(searchText: searchText, categoryKey: selectedCategoryKey, equipment: selectedEquipment)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()

                if viewModel.exercises.isEmpty {
                    emptyState
                } else {
                    exerciseList
                }
            }
            // On the ZStack, not exerciseList's ScrollView — safeAreaInset misbehaves
            // during interactive keyboard dismissal when on the same view (FB13296535).
            .keyboardDoneBar(isFocused: $isSearchFocused)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { exerciseId in
                if let exercise = viewModel.exercises.first(where: { $0.id == exerciseId }) {
                    ExerciseDetailView(exercise: exercise, viewModel: viewModel)
                }
            }
            .sheet(isPresented: $viewModel.showingAddExercise) {
                AddExerciseView(viewModel: viewModel)
            }
            .alert("exercises.delete.confirmation.title".localized, isPresented: $viewModel.showingDeleteConfirmation) {
                Button("common.cancel".localized, role: .cancel) {
                    viewModel.cancelDeleteExercise()
                }
                Button("exercises.delete.confirm".localized, role: .destructive) {
                    viewModel.confirmDeleteExercise()
                }
            } message: {
                let exerciseName = viewModel.exerciseToDelete?.name ?? ""
                if viewModel.routinesUsingExercise.isEmpty {
                    Text(String(format: "exercises.delete.confirmation.message_standalone".localized, exerciseName))
                } else {
                    let routineNames = viewModel.routinesUsingExercise.map(\.name).joined(separator: ", ")
                    Text(String(format: "exercises.delete.confirmation.message".localized, exerciseName, routineNames))
                }
            }
            .alert("exercises.deleteAll.confirmation.title".localized, isPresented: $viewModel.showingDeleteAllConfirmation) {
                Button("common.cancel".localized, role: .cancel) {
                    viewModel.cancelDeleteAllExercises()
                }
                Button("exercises.deleteAll.confirm".localized, role: .destructive) {
                    viewModel.confirmDeleteAllExercises()
                }
            } message: {
                Text("exercises.deleteAll.confirmation.message".localized)
            }
        }
        .onAppear {
            viewModel.fetchExercises()
        }
    }

    // MARK: - List

    private var exerciseList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 20)

                RedesignSearchBar(text: $searchText, placeholder: "exercises.search".localized, isFocused: $isSearchFocused)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                // Muscle category filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        FilterPillButton(label: "filter.all".localized, isActive: selectedCategoryKey == nil) {
                            withAnimation(.easeOut(duration: 0.15)) { selectedCategoryKey = nil }
                        }
                        ForEach(viewModel.availableCategoryKeys, id: \.self) { categoryKey in
                            FilterPillButton(
                                label: categoryKey.localized,
                                isActive: selectedCategoryKey == categoryKey,
                                color: MuscleGroups.categoryColor(for: categoryKey)
                            ) {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    selectedCategoryKey = selectedCategoryKey == categoryKey ? nil : categoryKey
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.top, 12)

                // Equipment filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        FilterPillButton(label: "filter.all_equipment".localized, isActive: selectedEquipment == nil) {
                            withAnimation(.easeOut(duration: 0.15)) { selectedEquipment = nil }
                        }
                        ForEach(viewModel.availableEquipment, id: \.self) { equipment in
                            FilterPillButton(
                                label: equipment.displayName,
                                isActive: selectedEquipment == equipment
                            ) {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    selectedEquipment = selectedEquipment == equipment ? nil : equipment
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.top, 8)

                // Grouped list
                if filteredSections.isEmpty {
                    Text("exercises.no_results".localized)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Color.white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    ForEach(filteredSections) { section in
                        sectionHeader(section)
                        VStack(spacing: 8) {
                            ForEach(section.exercises) { exercise in
                                NavigationLink(value: exercise.id) {
                                    ExerciseLibraryRowView(
                                        exercise: exercise,
                                        usedInCount: viewModel.routineUsageCount(for: exercise)
                                    )
                                }
                                .buttonStyle(.plain)
                                .simultaneousGesture(TapGesture().onEnded { HapticManager.shared.light() })
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }

                Color.clear.frame(height: 60)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func sectionHeader(_ section: ExerciseSection) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(MuscleGroups.categoryColor(for: section.categoryTitleKey))
                .frame(width: 8, height: 8)
            Text(section.localizedTitle)
                .font(.system(size: 14.5, weight: .bold, design: .rounded))
                .kerning(-0.3)
                .foregroundStyle(.white)
            Text("\(section.exercises.count)")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.4))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("exercises.title".localized)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .kerning(-0.7)
                    .foregroundStyle(.white)
                Text(String(
                    format: "exercises.header_meta".localized,
                    viewModel.exercises.count,
                    viewModel.availableCategoryKeys.count
                ))
                .font(.system(size: 12.5))
                .foregroundStyle(Color.white.opacity(0.45))
            }

            Spacer()

            #if DEBUG
            Button(role: .destructive) {
                viewModel.requestDeleteAllExercises()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.destructive)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("exercises.deleteAll.confirm".localized)
            #endif

            Button {
                HapticManager.shared.light()
                viewModel.showingAddExercise = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.tint)
                    .frame(width: 38, height: 38)
                    .background(DesignSystem.Colors.tint.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("exercises.add".localized)
        }
        .padding(.top, 8)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("exercises.empty.title".localized, systemImage: "dumbbell")
        } description: {
            Text("exercises.empty.description".localized)
        } actions: {
            Button("exercises.add".localized) {
                viewModel.showingAddExercise = true
            }
            .buttonStyle(.onyxProminent)
        }
    }
}

#Preview {
    Text("ExercisesView Preview")
}

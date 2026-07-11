import Foundation

/// One row of the built-in starter exercise catalog.
/// `seedKey` is the stable cross-device identity of the exercise AND its
/// Localizable.strings key for the display name.
struct SeedExercise {
    let seedKey: String
    let muscleGroups: [String]
    let equipmentType: EquipmentType
    let loadBehavior: ExerciseLoadBehavior
    /// Catalog version that introduced this row — rows are only inserted when
    /// upgrading past that version, so deleted seeds are never resurrected.
    let introducedInVersion: Int

    init(
        seedKey: String,
        muscleGroups: [String],
        equipmentType: EquipmentType,
        loadBehavior: ExerciseLoadBehavior = .resistance,
        introducedInVersion: Int
    ) {
        self.seedKey = seedKey
        self.muscleGroups = muscleGroups
        self.equipmentType = equipmentType
        self.loadBehavior = loadBehavior
        self.introducedInVersion = introducedInVersion
    }
}

/// The built-in starter exercise catalog. Append-only: never remove or rename
/// seedKeys; new exercises get introducedInVersion = the bumped currentVersion.
enum SeedExerciseCatalog {
    // Version 2 is the first shipped catalog: version 1 was an unreleased
    // interim policy (seed only empty libraries) — re-releasing the rows as
    // v2 backfills devices that already stamped v1 during development.
    static let currentVersion = 2

    static let entries: [SeedExercise] = [
        // MARK: - Chest
        SeedExercise(seedKey: "seed.exercise.barbell_bench_press", muscleGroups: ["Chest", "Front Delts", "Triceps"], equipmentType: .barbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.incline_barbell_bench_press", muscleGroups: ["Upper Chest", "Front Delts", "Triceps"], equipmentType: .barbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.decline_barbell_bench_press", muscleGroups: ["Chest", "Triceps"], equipmentType: .barbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.dumbbell_bench_press", muscleGroups: ["Chest", "Front Delts", "Triceps"], equipmentType: .dumbbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.incline_dumbbell_bench_press", muscleGroups: ["Upper Chest", "Front Delts", "Triceps"], equipmentType: .dumbbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.dumbbell_fly", muscleGroups: ["Chest"], equipmentType: .dumbbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.incline_dumbbell_fly", muscleGroups: ["Upper Chest"], equipmentType: .dumbbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.cable_fly", muscleGroups: ["Chest"], equipmentType: .cable, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.cable_crossover", muscleGroups: ["Chest"], equipmentType: .cable, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.machine_chest_press", muscleGroups: ["Chest", "Front Delts", "Triceps"], equipmentType: .machine, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.pec_deck", muscleGroups: ["Chest"], equipmentType: .machine, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.smith_machine_bench_press", muscleGroups: ["Chest", "Front Delts", "Triceps"], equipmentType: .machine, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.push_up", muscleGroups: ["Chest", "Triceps", "Front Delts"], equipmentType: .bodyweight, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.chest_dip", muscleGroups: ["Chest", "Triceps", "Front Delts"], equipmentType: .bodyweight, introducedInVersion: 2),

        // MARK: - Back
        SeedExercise(seedKey: "seed.exercise.deadlift", muscleGroups: ["Lower Back", "Glutes", "Hamstrings"], equipmentType: .barbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.rack_pull", muscleGroups: ["Lower Back", "Hamstrings"], equipmentType: .barbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.pull_up", muscleGroups: ["Lats", "Biceps", "Upper Back"], equipmentType: .bodyweight, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.chin_up", muscleGroups: ["Lats", "Biceps"], equipmentType: .bodyweight, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.inverted_row", muscleGroups: ["Upper Back", "Lats", "Biceps"], equipmentType: .bodyweight, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.barbell_row", muscleGroups: ["Upper Back", "Lats", "Biceps"], equipmentType: .barbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.pendlay_row", muscleGroups: ["Upper Back", "Lats"], equipmentType: .barbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.t_bar_row", muscleGroups: ["Upper Back", "Lats", "Biceps"], equipmentType: .barbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.dumbbell_row", muscleGroups: ["Lats", "Upper Back", "Biceps"], equipmentType: .dumbbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.lat_pulldown", muscleGroups: ["Lats", "Biceps"], equipmentType: .cable, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.close_grip_lat_pulldown", muscleGroups: ["Lats", "Biceps"], equipmentType: .cable, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.seated_cable_row", muscleGroups: ["Upper Back", "Lats", "Biceps"], equipmentType: .cable, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.straight_arm_pulldown", muscleGroups: ["Lats"], equipmentType: .cable, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.machine_row", muscleGroups: ["Upper Back", "Lats"], equipmentType: .machine, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.assisted_pull_up", muscleGroups: ["Lats", "Biceps"], equipmentType: .machine, loadBehavior: .counterweightAssistance, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.back_extension", muscleGroups: ["Lower Back", "Glutes", "Hamstrings"], equipmentType: .bodyweight, introducedInVersion: 2),

        // MARK: - Shoulders
        SeedExercise(seedKey: "seed.exercise.overhead_press", muscleGroups: ["Shoulders", "Front Delts", "Triceps"], equipmentType: .barbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.seated_dumbbell_shoulder_press", muscleGroups: ["Shoulders", "Front Delts", "Triceps"], equipmentType: .dumbbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.arnold_press", muscleGroups: ["Shoulders", "Front Delts"], equipmentType: .dumbbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.machine_shoulder_press", muscleGroups: ["Shoulders", "Front Delts", "Triceps"], equipmentType: .machine, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.dumbbell_lateral_raise", muscleGroups: ["Side Delts"], equipmentType: .dumbbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.cable_lateral_raise", muscleGroups: ["Side Delts"], equipmentType: .cable, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.machine_lateral_raise", muscleGroups: ["Side Delts"], equipmentType: .machine, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.dumbbell_front_raise", muscleGroups: ["Front Delts"], equipmentType: .dumbbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.dumbbell_rear_delt_fly", muscleGroups: ["Rear Delts"], equipmentType: .dumbbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.reverse_pec_deck", muscleGroups: ["Rear Delts"], equipmentType: .machine, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.face_pull", muscleGroups: ["Rear Delts", "Upper Back"], equipmentType: .cable, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.upright_row", muscleGroups: ["Side Delts", "Shoulders"], equipmentType: .barbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.barbell_shrug", muscleGroups: ["Upper Back"], equipmentType: .barbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.dumbbell_shrug", muscleGroups: ["Upper Back"], equipmentType: .dumbbell, introducedInVersion: 2),

        // MARK: - Arms
        SeedExercise(seedKey: "seed.exercise.barbell_curl", muscleGroups: ["Biceps"], equipmentType: .barbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.dumbbell_curl", muscleGroups: ["Biceps"], equipmentType: .dumbbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.hammer_curl", muscleGroups: ["Biceps", "Forearms"], equipmentType: .dumbbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.incline_dumbbell_curl", muscleGroups: ["Biceps"], equipmentType: .dumbbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.concentration_curl", muscleGroups: ["Biceps"], equipmentType: .dumbbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.preacher_curl", muscleGroups: ["Biceps"], equipmentType: .barbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.cable_curl", muscleGroups: ["Biceps"], equipmentType: .cable, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.machine_bicep_curl", muscleGroups: ["Biceps"], equipmentType: .machine, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.reverse_curl", muscleGroups: ["Forearms", "Biceps"], equipmentType: .barbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.wrist_curl", muscleGroups: ["Forearms"], equipmentType: .dumbbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.tricep_pushdown", muscleGroups: ["Triceps"], equipmentType: .cable, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.rope_pushdown", muscleGroups: ["Triceps"], equipmentType: .cable, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.overhead_tricep_extension", muscleGroups: ["Triceps"], equipmentType: .dumbbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.skull_crusher", muscleGroups: ["Triceps"], equipmentType: .barbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.close_grip_bench_press", muscleGroups: ["Triceps", "Chest"], equipmentType: .barbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.bench_dip", muscleGroups: ["Triceps"], equipmentType: .bodyweight, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.machine_tricep_extension", muscleGroups: ["Triceps"], equipmentType: .machine, introducedInVersion: 2),

        // MARK: - Core
        SeedExercise(seedKey: "seed.exercise.plank", muscleGroups: ["Abs"], equipmentType: .bodyweight, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.side_plank", muscleGroups: ["Obliques"], equipmentType: .bodyweight, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.crunch", muscleGroups: ["Abs"], equipmentType: .bodyweight, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.sit_up", muscleGroups: ["Abs"], equipmentType: .bodyweight, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.bicycle_crunch", muscleGroups: ["Abs", "Obliques"], equipmentType: .bodyweight, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.cable_crunch", muscleGroups: ["Abs"], equipmentType: .cable, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.machine_crunch", muscleGroups: ["Abs"], equipmentType: .machine, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.hanging_leg_raise", muscleGroups: ["Abs", "Hip Flexors"], equipmentType: .bodyweight, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.lying_leg_raise", muscleGroups: ["Abs", "Hip Flexors"], equipmentType: .bodyweight, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.russian_twist", muscleGroups: ["Obliques", "Abs"], equipmentType: .bodyweight, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.mountain_climber", muscleGroups: ["Abs"], equipmentType: .bodyweight, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.ab_wheel_rollout", muscleGroups: ["Abs"], equipmentType: .bodyweight, introducedInVersion: 2),

        // MARK: - Legs
        SeedExercise(seedKey: "seed.exercise.barbell_back_squat", muscleGroups: ["Quadriceps", "Glutes", "Hamstrings"], equipmentType: .barbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.front_squat", muscleGroups: ["Quadriceps", "Glutes"], equipmentType: .barbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.smith_machine_squat", muscleGroups: ["Quadriceps", "Glutes"], equipmentType: .machine, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.hack_squat", muscleGroups: ["Quadriceps", "Glutes"], equipmentType: .machine, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.leg_press", muscleGroups: ["Quadriceps", "Glutes", "Hamstrings"], equipmentType: .machine, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.goblet_squat", muscleGroups: ["Quadriceps", "Glutes"], equipmentType: .dumbbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.bulgarian_split_squat", muscleGroups: ["Quadriceps", "Glutes"], equipmentType: .dumbbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.walking_lunge", muscleGroups: ["Quadriceps", "Glutes"], equipmentType: .dumbbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.lunge", muscleGroups: ["Quadriceps", "Glutes"], equipmentType: .bodyweight, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.step_up", muscleGroups: ["Quadriceps", "Glutes"], equipmentType: .dumbbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.leg_extension", muscleGroups: ["Quadriceps"], equipmentType: .machine, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.lying_leg_curl", muscleGroups: ["Hamstrings"], equipmentType: .machine, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.seated_leg_curl", muscleGroups: ["Hamstrings"], equipmentType: .machine, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.romanian_deadlift", muscleGroups: ["Hamstrings", "Glutes", "Lower Back"], equipmentType: .barbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.stiff_leg_deadlift", muscleGroups: ["Hamstrings", "Glutes"], equipmentType: .barbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.sumo_deadlift", muscleGroups: ["Glutes", "Hamstrings", "Quadriceps"], equipmentType: .barbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.hip_thrust", muscleGroups: ["Glutes", "Hamstrings"], equipmentType: .barbell, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.glute_bridge", muscleGroups: ["Glutes"], equipmentType: .bodyweight, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.cable_glute_kickback", muscleGroups: ["Glutes"], equipmentType: .cable, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.hip_abduction_machine", muscleGroups: ["Glutes"], equipmentType: .machine, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.standing_calf_raise", muscleGroups: ["Calves"], equipmentType: .machine, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.seated_calf_raise", muscleGroups: ["Calves"], equipmentType: .machine, introducedInVersion: 2),
        SeedExercise(seedKey: "seed.exercise.leg_press_calf_raise", muscleGroups: ["Calves"], equipmentType: .machine, introducedInVersion: 2),
    ]
}

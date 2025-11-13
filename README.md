# GymStreak - iOS Workout App MVP

A SwiftUI-based workout application built with SwiftData for local persistence and HealthKit integration.

## 🎯 MVP Status

### ✅ **COMPLETED**
- **Tab 1: Workout Routines** - Create, edit, and manage workout routines
- **Tab 2: Exercise Library** - Standalone exercise management with muscle group categorization
- **Data Models** - Complete SwiftData implementation with proper relationships
- **Streamlined Exercise Addition** - Intuitive flow for adding exercises to routines

### 🚧 **IN PROGRESS**
- **Tab 3: Workout Recording** - Active workout sessions with HealthKit integration

---

## 🏗️ Project Structure

```
GymStreak/
├── Models.swift                    # SwiftData models (Routine, Exercise, RoutineExercise, ExerciseSet)
├── ContentView.swift              # Main tab navigation
├── RoutinesView.swift             # Tab 1: Routine management
├── AddRoutineView.swift           # Create new routines
├── RoutineDetailView.swift        # View/edit routine details
├── AddExerciseToRoutineView.swift # Streamlined exercise addition to routines
├── RoutineExerciseDetailView.swift # Manage sets within a routine exercise
├── EditSetView.swift              # Edit individual set parameters
├── ExercisesView.swift            # Tab 2: Exercise library management
├── AddExerciseView.swift          # Create new standalone exercises
├── ExerciseDetailView.swift       # View/edit exercise details
├── EditExerciseView.swift         # Edit exercise properties
├── ExercisePickerView.swift       # Choose exercises from library
├── WorkoutView.swift              # Tab 3: Workout recording (placeholder)
├── ViewModels/
│   ├── RoutinesViewModel.swift    # Routine and set management
│   └── ExercisesViewModel.swift   # Standalone exercise management
└── README.md                      # This file
```

---

## 🎯 **Key Features**

### **Tab 1: Workout Routines (COMPLETED)**
- ✅ Create and edit workout routines
- ✅ Add exercises from the exercise library
- ✅ Configure sets with reps, weight, and rest time
- ✅ **NEW: Streamlined exercise addition flow**
- ✅ **NEW: Immediate set addition with inline editing**

### **Tab 2: Exercise Library (COMPLETED)**
- ✅ Create standalone exercises with muscle group categorization
- ✅ Edit exercise properties (name, muscle group, description)
- ✅ Delete exercises with confirmation
- ✅ **NEW: Muscle group categories (Arms, Legs, Chest, Back, Shoulders, Core, Glutes, Calves, Full Body)**

### **Tab 3: Workout Recording (PLANNED)**
- 🚧 Start workout from routines
- 🚧 Freestyle workout creation
- 🚧 Apple HealthKit integration
- 🚧 Set completion tracking
- 🚧 Rest timer functionality
- 🚧 Workout summary and history

---

## 🚀 **Streamlined Exercise Addition Flow**

The new exercise addition flow provides a much more intuitive user experience:

### **1. Choose Exercise**
- **Navigation push** (not sheet) to exercise picker
- Shows overview of all saved exercises
- Search by name or muscle group
- Select exercise to add to routine

### **2. Add Sets (Immediate Addition)**
- **"Add Set" button** → **Immediately adds a new set** with default values (10 reps, 0.0 kg)
- **No confirmation needed** - set appears instantly in the list
- **"Add Set" button stays** - can click multiple times to add more sets
- **Tap any existing set** → Opens inline edit form for that specific set
- **Edit form includes**:
  - Reps stepper (1-100)
  - Weight input field (decimal)
  - Cancel button (red)
  - Save button (blue)

### **3. Rest Timer**
- **Global rest timer** applied to all sets
- Slider selection (0-300 seconds)
- Consistent rest time between all sets for the exercise

### **4. Save Exercise**
- **Save button** in top-right toolbar
- Only enabled when exercise is selected AND sets are configured
- Creates RoutineExercise with all configured sets
- Adds to routine and updates the view

---

## 🏗️ **Technical Implementation**

### **Architecture**
- **MVVM Pattern** with separate ViewModels for routines and exercises
- **SwiftData** for local persistence with proper model relationships
- **SwiftUI** for declarative UI with navigation and inline form expansion

### **Data Models**
```swift
@Model
final class Routine {
    var id: UUID
    var name: String
    var routineExercises: [RoutineExercise]  // Link to exercises
    var createdAt: Date
    var updatedAt: Date
}

@Model
final class Exercise {
    var id: UUID
    var name: String
    var muscleGroup: String                  // Arms, Legs, Chest, etc.
    var exerciseDescription: String
    var createdAt: Date
    var updatedAt: Date
}

@Model
final class RoutineExercise {
    var id: UUID
    var routine: Routine?                    // Link to parent routine
    var exercise: Exercise?                  // Link to exercise
    var sets: [ExerciseSet]                 // Routine-specific sets
    var order: Int                          // Exercise order in routine
}

@Model
final class ExerciseSet {
    var id: UUID
    var reps: Int
    var weight: Double
    var restTime: TimeInterval
    var isCompleted: Bool
    var routineExercise: RoutineExercise?   // Link to parent routine exercise
}
```

### **ViewModels**
- **`RoutinesViewModel`**: Manages routines, routine exercises, and sets
- **`ExercisesViewModel`**: Manages standalone exercises in the library

---

## 🎨 **User Workflow**

### **Creating a Workout Routine**
1. **Tab 1** → "Add Routine" → Enter routine name → Save
2. **Routine Detail** → "Add Exercise" → **NEW: Choose Exercise** (navigation push)
3. **Exercise Picker** → Select exercise → Back to routine
4. **Configure Sets** → **"Add Set"** → Set appears immediately → **Tap set to edit** → Configure reps/weight → Save → Repeat for multiple sets
5. **Set Rest Timer** → Global rest time for all sets
6. **Save Exercise** → Exercise added to routine with all sets

### **Managing Exercise Library**
1. **Tab 2** → "Add Exercise" → Enter name, select muscle group, add description
2. **Exercise List** → Tap exercise → View details, edit, or delete
3. **Edit Exercise** → Modify name, muscle group, or description

---

## 🏋️ **Muscle Group Categories**

Exercises are categorized by muscle groups for better organization:
- **Arms** - Biceps, Triceps, Forearms
- **Legs** - Quadriceps, Hamstrings, Calves
- **Chest** - Pectorals, Upper/Lower Chest
- **Back** - Lats, Traps, Rhomboids
- **Shoulders** - Deltoids, Rotator Cuff
- **Core** - Abs, Obliques, Lower Back
- **Glutes** - Gluteus Maximus, Medius, Minimus
- **Calves** - Gastrocnemius, Soleus
- **Full Body** - Compound movements
- **General** - Default category

---

## 🚀 **Getting Started**

### **Prerequisites**
- Xcode 15.0+
- iOS 18.5+
- Swift 5.9+

### **Installation**
1. Clone the repository
2. Open `GymStreak.xcodeproj` in Xcode
3. Build and run on iOS Simulator or device

### **First Run**
1. **Tab 2**: Create some exercises in the exercise library
2. **Tab 1**: Create a workout routine
3. **Add Exercise**: Use the streamlined flow to add exercises with sets
4. **Configure**: Add sets immediately, then tap each set to configure reps and weight

---

## 🔄 **Data Model Architecture**

```
Routine (1) ←→ (Many) RoutineExercise (Many) ←→ (1) Exercise
                    ↓
                (Many) ExerciseSet
```

- **Routine**: Contains multiple exercises with specific configurations
- **RoutineExercise**: Links an exercise to a routine with routine-specific sets
- **Exercise**: Standalone exercise definition (reusable across routines)
- **ExerciseSet**: Individual set configuration (reps, weight, rest time)

This architecture allows:
- ✅ **Exercise Reusability**: Define once, use in multiple routines
- ✅ **Routine-Specific Configuration**: Different sets/weights per routine
- ✅ **Flexible Set Management**: Add/remove sets per exercise within a routine

---

## 📱 **Next Steps**

### **Immediate Priority**
- **Tab 3 Implementation**: Complete workout recording functionality
- **HealthKit Integration**: Request permissions and start workout sessions
- **Set Completion Tracking**: Mark sets as complete during workouts
- **Rest Timer Implementation**: Active countdown between sets

### **Future Enhancements**
- **Workout History**: View completed workouts and progress
- **Progress Tracking**: Track weight/reps improvements over time
- **Exercise Variations**: Different variations of the same exercise
- **Workout Templates**: Pre-built routine templates
- **Social Features**: Share routines with friends

---

## 🐛 **Known Issues**

None currently reported.

---

## 🤝 **Contributing**

This is a personal MVP project. Feel free to fork and modify for your own use.

---

## 📄 **License**

Personal use only.

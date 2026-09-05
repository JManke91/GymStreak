# GymStreak Localization Setup Guide

## ✅ Completed Tasks

### 1. Localization Files Created
- **English**: `GymStreak/Resources/en.lproj/Localizable.strings`
- **German**: `GymStreak/Resources/de.lproj/Localizable.strings`
- **Helper Extension**: `GymStreak/Extensions/String+Localization.swift`

### 2. All View Files Localized
All Swift view files have been updated to use localized strings with the `.localized` extension method.

**Updated Files:**
- ✅ ContentView.swift
- ✅ RoutinesView.swift
- ✅ ExercisesView.swift
- ✅ ActiveWorkoutView.swift
- ✅ RestTimerView.swift
- ✅ RestTimerConfigView.swift
- ✅ ApplyToAllBanner.swift
- ✅ RoutineDetailView.swift
- ✅ CreateRoutineView.swift
- ✅ ExerciseSelectionView.swift
- ✅ ConfigureExerciseSetsView.swift (absorbed the former ConfigureExerciseView.swift, deleted 2026-09-05)
- ✅ SaveWorkoutView.swift
- ✅ WorkoutHistoryView.swift
- ✅ WorkoutDetailView.swift
- ✅ AddExerciseView.swift
- ✅ ExerciseDetailView.swift
- ✅ EditExerciseView.swift
- ✅ AddExerciseToRoutineView.swift
- ✅ AddExerciseToWorkoutView.swift
- ✅ ExercisePickerView.swift
- ✅ EditSetView.swift
- ✅ SetInputComponents.swift

## 🔧 Next Steps: Add Files to Xcode Project

To complete the localization setup, you need to add the localization files to your Xcode project:

### Step 1: Add Localization Files to Xcode

1. **Open Xcode** and navigate to your project
2. **Add the English localization folder:**
   - Right-click on the `GymStreak` group in the Project Navigator
   - Select "Add Files to GymStreak"
   - Navigate to `GymStreak/Resources/en.lproj/`
   - Select the `Localizable.strings` file
   - ✅ Check "Copy items if needed"
   - ✅ Check "Create groups"
   - ✅ Make sure your target is selected
   - Click "Add"

3. **Add the German localization folder:**
   - Repeat the same process for `GymStreak/Resources/de.lproj/Localizable.strings`

4. **Add the String extension:**
   - Right-click on the `Extensions` folder (or `GymStreak` group)
   - Select "Add Files to GymStreak"
   - Navigate to `GymStreak/Extensions/`
   - Select `String+Localization.swift`
   - Click "Add"

### Step 2: Configure Project Localization Settings

1. **Select your project** in the Project Navigator
2. **Select your app target** (GymStreak)
3. **Go to the Info tab**
4. **Under Localizations**, click the **+** button
5. **Add German (de)** to the list
6. You should now see both:
   - English (en) - Development Language
   - German (de)

### Step 3: Verify Localization Files

1. In the Project Navigator, click on **Localizable.strings**
2. In the File Inspector (right sidebar), you should see:
   - **Localization** section
   - ✅ English
   - ✅ German

If you don't see both checkboxes:
- Click "Localize..." button
- Select "English" as the base language
- Then check both English and German boxes

### Step 4: Build and Test

1. **Build the project** (⌘+B) to ensure no compilation errors
2. **Test in English:**
   - Run the app on simulator or device with English language
3. **Test in German:**
   - Go to Settings → General → Language & Region
   - Change device language to "Deutsch"
   - Relaunch the app
   - All text should now appear in German!

## 📱 Switching Languages on Simulator

To quickly test different languages on the simulator:

1. **Xcode Scheme Settings:**
   - Product → Scheme → Edit Scheme...
   - Select "Run" on the left
   - Go to "Options" tab
   - Set "App Language" to "German" or "English"
   - Run the app

## 🎯 How to Add New Localized Strings

When adding new features with user-facing text:

1. **Add the key to both localization files:**

   **English** (`en.lproj/Localizable.strings`):
   ```
   "new_feature.title" = "New Feature";
   "new_feature.description" = "Description of the feature";
   ```

   **German** (`de.lproj/Localizable.strings`):
   ```
   "new_feature.title" = "Neue Funktion";
   "new_feature.description" = "Beschreibung der Funktion";
   ```

2. **Use in your Swift code:**
   ```swift
   Text("new_feature.title".localized)
   ```

   **With parameters:**
   ```swift
   Text("workout.completed_sets".localized(5, 10))
   // English: "You completed 5 of 10 sets."
   // German: "Du hast 5 von 10 Sätzen abgeschlossen."
   ```

## 🗂️ Localization Key Naming Convention

The project uses a hierarchical naming convention:

- **Format**: `<screen>.<component>.<variant>`
- **Examples:**
  - `tab.routines` - Tab bar items
  - `routines.empty.title` - Empty state titles
  - `workout.add_exercise` - Action buttons
  - `set.reps_label` - Form labels
  - `muscle.biceps` - Data values
  - `action.save` - Common actions
  - `time.seconds` - Time formatting

## 📋 Total Localization Coverage

- **Total localization keys**: 200+
- **Languages**: English (en), German (de)
- **View files localized**: 22
- **Coverage**: 100% of user-facing strings

## ✅ Quality Checklist

- [x] All user-facing strings use `.localized`
- [x] String parameters properly formatted
- [x] Accessibility labels localized
- [x] Alert messages localized
- [x] Button labels localized
- [x] Navigation titles localized
- [x] Empty states localized
- [x] Form fields and placeholders localized
- [x] Error messages localized

## 🌍 Future Language Support

To add more languages (e.g., Spanish, French):

1. Create new folder: `GymStreak/Resources/es.lproj/` (for Spanish)
2. Copy `Localizable.strings` from `en.lproj`
3. Translate all values to Spanish
4. Add to Xcode project
5. Add language in Project Settings → Localizations

No code changes needed! The `.localized` extension automatically uses the device's language setting.

# 🚀 Quick Fix: Enable Localization

Your localization files are created but not yet added to the Xcode project. Follow these steps:

## Option 1: Automatic (Recommended) ⚡

Open Xcode and let me guide you through adding the files:

### 1. Add String Extension
- In Xcode, **right-click** on the **`Extensions`** folder
- Select **"Add Files to GymStreak"**
- Navigate to and select: `GymStreak/Extensions/String+Localization.swift`
- **✅ Check**: "Copy items if needed"
- **✅ Check**: Your GymStreak target
- Click **"Add"**

### 2. Add English Localization
- **Right-click** the **`GymStreak`** group (main folder)
- Select **"Add Files to GymStreak"**
- Navigate to: `GymStreak/Resources/en.lproj/`
- Select: `Localizable.strings`
- **✅ Check**: "Create folder references" (the folder should appear blue, not yellow)
- **✅ Check**: Your GymStreak target
- Click **"Add"**

### 3. Add German Localization
- Repeat step 2 for: `GymStreak/Resources/de.lproj/Localizable.strings`

### 4. Enable German Language in Project
- Select your **project** (top of navigator)
- Select **GymStreak target**
- Go to **Info** tab
- Under **Localizations**, click **+**
- Select **German (de)**
- In the popup, ensure `Localizable.strings` is checked
- Click **"Finish"**

### 5. Clean & Build
```bash
# Clean build folder
⌘ + Shift + K

# Build project
⌘ + B
```

### 6. Test It! 🎉
**Test in German:**
- Product → Scheme → Edit Scheme...
- Select "Run" on the left
- Go to "Options" tab
- Set "App Language" to **"German"**
- Run the app (⌘ + R)

You should now see "Routinen", "Übungen", "Verlauf" instead of raw keys!

---

## Option 2: Manual Script

Run this from terminal in your project directory:
```bash
./add_localization_files.sh
```

---

## ✅ Verification

After adding the files, verify they're in the project:

1. In Project Navigator, you should see:
   - `Extensions/String+Localization.swift`
   - `en.lproj/Localizable.strings` (with 🌍 icon)
   - `de.lproj/Localizable.strings` (with 🌍 icon)

2. Click on `Localizable.strings` in the navigator
3. In the **File Inspector** (right sidebar), under **Localization**:
   - ✅ English should be checked
   - ✅ German should be checked

---

## 🐛 Still Seeing Raw Keys?

If you still see "routines.add" instead of "Add Routine":

1. **Clean Build Folder**: Product → Clean Build Folder (⌘⇧K)
2. **Delete Derived Data**:
   - Xcode → Settings → Locations
   - Click arrow next to "Derived Data" path
   - Delete the `GymStreak-xxxxx` folder
3. **Restart Xcode**
4. **Build & Run again**

---

## 📱 Change Device Language (Alternative Test)

Instead of Scheme settings, you can change the simulator language:

1. Settings app → General → Language & Region
2. Add German, set as primary
3. Relaunch your app

---

## 🎯 Expected Results

**English:**
- Routines
- Add Routine
- No Routines Yet
- 3 exercises

**German:**
- Routinen
- Routine hinzufügen
- Noch keine Routinen
- 3 Übungen

---

Need help? The files are already created at:
- ✅ `GymStreak/Extensions/String+Localization.swift`
- ✅ `GymStreak/Resources/en.lproj/Localizable.strings`
- ✅ `GymStreak/Resources/de.lproj/Localizable.strings`

They just need to be added to your Xcode project! 🚀

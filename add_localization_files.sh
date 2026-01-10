#!/bin/bash

# Script to add localization files to Xcode project
# Run this from the project root directory

echo "🌍 Adding localization files to Xcode project..."
echo ""

# Check if we're in the right directory
if [ ! -f "GymStreak.xcodeproj/project.pbxproj" ]; then
    echo "❌ Error: Must run this script from the project root directory"
    echo "   (the directory containing GymStreak.xcodeproj)"
    exit 1
fi

# Check if files exist
if [ ! -f "GymStreak/Extensions/String+Localization.swift" ]; then
    echo "❌ Error: String+Localization.swift not found"
    exit 1
fi

if [ ! -f "GymStreak/Resources/en.lproj/Localizable.strings" ]; then
    echo "❌ Error: English Localizable.strings not found"
    exit 1
fi

if [ ! -f "GymStreak/Resources/de.lproj/Localizable.strings" ]; then
    echo "❌ Error: German Localizable.strings not found"
    exit 1
fi

echo "✅ All files found!"
echo ""
echo "📋 Please follow these manual steps in Xcode:"
echo ""
echo "STEP 1: Add String+Localization.swift"
echo "  1. Open GymStreak.xcodeproj in Xcode"
echo "  2. Right-click the 'Extensions' folder in Project Navigator"
echo "  3. Select 'Add Files to GymStreak'"
echo "  4. Navigate to: GymStreak/Extensions/"
echo "  5. Select: String+Localization.swift"
echo "  6. ✅ Check 'Copy items if needed'"
echo "  7. ✅ Check your target (GymStreak)"
echo "  8. Click 'Add'"
echo ""
echo "STEP 2: Add English localization"
echo "  1. Right-click the 'GymStreak' group in Project Navigator"
echo "  2. Select 'Add Files to GymStreak'"
echo "  3. Navigate to: GymStreak/Resources/en.lproj/"
echo "  4. Select: Localizable.strings"
echo "  5. ✅ Check 'Copy items if needed' if asked"
echo "  6. ✅ Check 'Create folder references' (NOT groups)"
echo "  7. ✅ Check your target (GymStreak)"
echo "  8. Click 'Add'"
echo ""
echo "STEP 3: Add German localization"
echo "  1. Repeat the same steps for: GymStreak/Resources/de.lproj/Localizable.strings"
echo ""
echo "STEP 4: Configure localization in Xcode"
echo "  1. Select your project in Project Navigator"
echo "  2. Select the 'GymStreak' target"
echo "  3. Go to the 'Info' tab"
echo "  4. Under 'Localizations', click '+'"
echo "  5. Add 'German (de)'"
echo "  6. In the dialog, find and check 'Localizable.strings'"
echo "  7. Click 'Finish'"
echo ""
echo "STEP 5: Verify and Build"
echo "  1. Clean build folder: Product → Clean Build Folder (⌘⇧K)"
echo "  2. Build project: Product → Build (⌘B)"
echo "  3. Run the app"
echo ""
echo "🎯 To test in German:"
echo "  • Edit Scheme → Run → Options"
echo "  • Set 'App Language' to 'German'"
echo "  • Run the app"
echo ""

# Try to open Xcode project (if on macOS)
if command -v open &> /dev/null; then
    read -p "Would you like to open the project in Xcode now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        open GymStreak.xcodeproj
    fi
fi

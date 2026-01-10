#!/bin/bash

# Verification script to check if localization is properly set up

echo "🔍 Verifying Localization Setup..."
echo ""

# Check if files exist in project
PROJECT_FILE="GymStreak.xcodeproj/project.pbxproj"

if [ ! -f "$PROJECT_FILE" ]; then
    echo "❌ Error: Project file not found"
    exit 1
fi

# Check for String+Localization.swift
if grep -q "String+Localization.swift" "$PROJECT_FILE"; then
    echo "✅ String+Localization.swift is in project"
else
    echo "❌ String+Localization.swift NOT in project"
    echo "   → Add it from GymStreak/Extensions/"
fi

# Check for English localization
if grep -q "en.lproj" "$PROJECT_FILE" && grep -q "Localizable.strings" "$PROJECT_FILE"; then
    echo "✅ English localization (en.lproj/Localizable.strings) is in project"
else
    echo "❌ English localization NOT in project"
    echo "   → Add GymStreak/Resources/en.lproj/Localizable.strings"
fi

# Check for German localization
if grep -q "de.lproj" "$PROJECT_FILE"; then
    echo "✅ German localization (de.lproj) is in project"
else
    echo "❌ German localization NOT in project"
    echo "   → Add GymStreak/Resources/de.lproj/Localizable.strings"
fi

# Check development region
if grep -q "developmentRegion = en" "$PROJECT_FILE"; then
    echo "✅ Development region is English"
else
    echo "⚠️  Development region may need to be set to English"
fi

# Check if known localizations include German
if grep -q "knownRegions" "$PROJECT_FILE"; then
    if grep -A 5 "knownRegions" "$PROJECT_FILE" | grep -q "de"; then
        echo "✅ German (de) is in known regions"
    else
        echo "⚠️  German (de) may not be in known regions"
        echo "   → Add German in Project Settings → Info → Localizations"
    fi
fi

echo ""
echo "📋 Next Steps:"
echo ""

# Count how many issues
ISSUES=0
if ! grep -q "String+Localization.swift" "$PROJECT_FILE"; then
    ISSUES=$((ISSUES + 1))
fi
if ! (grep -q "en.lproj" "$PROJECT_FILE" && grep -q "Localizable.strings" "$PROJECT_FILE"); then
    ISSUES=$((ISSUES + 1))
fi
if ! grep -q "de.lproj" "$PROJECT_FILE"; then
    ISSUES=$((ISSUES + 1))
fi

if [ $ISSUES -eq 0 ]; then
    echo "🎉 All files appear to be in the project!"
    echo ""
    echo "✅ Now do:"
    echo "   1. Clean Build Folder (⌘⇧K)"
    echo "   2. Build (⌘B)"
    echo "   3. Run the app"
    echo ""
    echo "🧪 To test in German:"
    echo "   • Edit Scheme → Run → Options → App Language: German"
    echo ""
else
    echo "⚠️  Found $ISSUES issue(s) - See QUICK_FIX.md for instructions"
    echo ""
    echo "📖 Quick guide:"
    echo "   1. Open Xcode"
    echo "   2. Add missing files (see errors above)"
    echo "   3. Run this script again to verify"
    echo ""
    echo "For detailed instructions: cat QUICK_FIX.md"
fi

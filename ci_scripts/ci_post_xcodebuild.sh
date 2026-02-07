#!/bin/sh

# ci_post_xcodebuild.sh
# This script runs after Xcode Cloud builds
# It generates App Store screenshots and uploads them

set -e  # Exit on error

echo "========================================="
echo "Checking if screenshot generation is needed"
echo "========================================="

# Only run screenshot generation if explicitly requested
# You can trigger this via workflow environment variables
if [ "$GENERATE_SCREENSHOTS" != "true" ]; then
    echo "Screenshot generation not requested. Skipping."
    echo "Set GENERATE_SCREENSHOTS=true in workflow to enable."
    exit 0
fi

echo "========================================="
echo "Generating App Store Screenshots"
echo "========================================="

# Navigate to project root
cd "$CI_PRIMARY_REPOSITORY_PATH"

# Install Ruby dependencies
echo "Installing Fastlane dependencies..."
bundle install

# Run Fastlane screenshots lane
echo "Running screenshot generation..."
bundle exec fastlane screenshots

echo "========================================="
echo "Screenshots generated successfully"
echo "========================================="

# Copy screenshots to artifacts
if [ -n "$CI_ARTIFACTS_PATH" ]; then
    echo "Copying screenshots to artifacts..."
    mkdir -p "$CI_ARTIFACTS_PATH/screenshots"
    cp -R fastlane/screenshots/* "$CI_ARTIFACTS_PATH/screenshots/"
    echo "Screenshots available in build artifacts"
fi

# Optional: Upload to App Store Connect
# Uncomment the following to auto-upload screenshots
# echo "Uploading screenshots to App Store Connect..."
# bundle exec fastlane upload_screenshots

echo "========================================="
echo "Screenshot workflow complete"
echo "========================================="

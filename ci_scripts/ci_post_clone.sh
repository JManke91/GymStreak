#!/bin/sh

set -e  # Exit on error

echo "========================================="
echo "Installing Fastlane and Dependencies"
echo "========================================="

# Xcode Cloud uses Homebrew-installed Ruby
# Install bundler if not present
if ! command -v bundle &> /dev/null; then
    echo "Installing bundler..."
    gem install bundler --no-document
fi

# Install Ruby dependencies from Gemfile
echo "Installing gems from Gemfile..."
bundle install

echo "========================================="
echo "Fastlane installation complete"
echo "========================================="

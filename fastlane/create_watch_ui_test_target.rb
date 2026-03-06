#!/usr/bin/env ruby

# Script to programmatically add GymStreakWatchUITests UI test target
# Uses the xcodeproj gem (available via Bundler through Fastlane)

require 'xcodeproj'
require 'fileutils'

PROJECT_PATH = File.expand_path('../GymStreak.xcodeproj', __dir__)
TARGET_NAME = 'GymStreakWatchUITests'
TEST_DIR = File.expand_path('../GymStreakWatchUITests', __dir__)

def create_watch_ui_test_target
  project = Xcodeproj::Project.open(PROJECT_PATH)

  # Check if target already exists
  if project.targets.any? { |t| t.name == TARGET_NAME }
    puts "Target '#{TARGET_NAME}' already exists, skipping creation."
    return
  end

  # Find the watch app target (test host)
  watch_target = project.targets.find { |t| t.name == 'GymStreakWatch Watch App' }
  unless watch_target
    puts "ERROR: Could not find 'GymStreakWatch Watch App' target"
    exit 1
  end

  # Get watch app deployment target
  watch_deployment = watch_target.build_configurations.first
    .build_settings['WATCHOS_DEPLOYMENT_TARGET'] || '26.0'

  puts "Creating '#{TARGET_NAME}' target..."
  puts "  Watch deployment target: #{watch_deployment}"

  # Create the UI testing bundle target
  test_target = project.new_target(
    :ui_test_bundle,
    TARGET_NAME,
    :watchos,
    watch_deployment
  )

  # Add dependency on the watch app target
  test_target.add_dependency(watch_target)

  # Configure build settings for both configurations
  test_target.build_configurations.each do |config|
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.shotat24fps.GymStreakWatchUITests'
    config.build_settings['TEST_TARGET_NAME'] = 'GymStreakWatch Watch App'
    config.build_settings['SDKROOT'] = 'watchos'
    config.build_settings['SUPPORTED_PLATFORMS'] = 'watchos watchsimulator'
    config.build_settings['TARGETED_DEVICE_FAMILY'] = '4'
    config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    config.build_settings['SWIFT_VERSION'] = '6.0'
    config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
    config.build_settings['DEVELOPMENT_TEAM'] = 'F89C86WVJX'
    config.build_settings['WATCHOS_DEPLOYMENT_TARGET'] = watch_deployment
    config.build_settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
    # Remove iOS-specific settings that the template may have added
    config.build_settings.delete('IPHONEOS_DEPLOYMENT_TARGET')
  end

  # Create the test directory if it doesn't exist
  FileUtils.mkdir_p(TEST_DIR)

  # Add synchronized root group for the test directory
  group = project.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedRootGroup)
  group.path = TARGET_NAME
  group.source_tree = '<group>'
  project.main_group.children << group
  test_target.file_system_synchronized_groups << group

  project.save

  puts "Target '#{TARGET_NAME}' created successfully."
  puts "Creating shared scheme..."

  create_shared_scheme(project)
end

def create_shared_scheme(project)
  test_target = project.targets.find { |t| t.name == TARGET_NAME }
  watch_target = project.targets.find { |t| t.name == 'GymStreakWatch Watch App' }

  scheme = Xcodeproj::XCScheme.new

  # Build action: build the watch app for testing
  build_entry = Xcodeproj::XCScheme::BuildAction::Entry.new(watch_target)
  build_entry.build_for_testing = true
  build_entry.build_for_running = true
  build_entry.build_for_profiling = false
  build_entry.build_for_archiving = false
  build_entry.build_for_analyzing = false
  scheme.build_action.add_entry(build_entry)
  scheme.build_action.parallelize_buildables = true
  scheme.build_action.build_implicit_dependencies = true

  # Test action: run the watch UI tests
  testable = Xcodeproj::XCScheme::TestAction::TestableReference.new(test_target)
  testable.skipped = false
  testable.parallelizable = true
  scheme.test_action.add_testable(testable)
  scheme.test_action.build_configuration = 'Debug'
  scheme.test_action.should_use_launch_scheme_args_env = true

  # Launch action
  scheme.launch_action.build_configuration = 'Debug'

  # Save as shared scheme
  scheme_dir = File.join(PROJECT_PATH, 'xcshareddata', 'xcschemes')
  FileUtils.mkdir_p(scheme_dir)
  scheme.save_as(PROJECT_PATH, TARGET_NAME, true)

  puts "Shared scheme '#{TARGET_NAME}' created."
end

# Run
create_watch_ui_test_target

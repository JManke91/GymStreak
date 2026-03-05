#!/usr/bin/env ruby

# Script to temporarily disable Watch app dependency for simulator builds
# This allows UI tests to build without requiring the Watch app
# Uses pattern matching instead of hardcoded IDs for robustness

require 'fileutils'

PROJECT_FILE = '../GymStreak.xcodeproj/project.pbxproj'
BACKUP_FILE = './project.pbxproj.backup'

def disable_watch_dependency
  puts "Disabling Watch app dependency and embed phase for simulator build..."

  # Create backup
  FileUtils.cp(PROJECT_FILE, BACKUP_FILE)

  # Read project file
  content = File.read(PROJECT_FILE)

  # Remove the Watch app target dependency reference (in dependencies array)
  # Matches: <whitespace><ID> /* PBXTargetDependency */,<newline>
  # But only the one that references the Watch target
  # First find the Watch dependency ID
  watch_dep_id = nil
  content.scan(/(\w+) \/\* PBXTargetDependency \*\/ = \{\s*isa = PBXTargetDependency;\s*target = \w+ \/\* GymStreakWatch Watch App \*\//) do |match|
    watch_dep_id = match[0]
  end

  if watch_dep_id
    # Remove from dependencies arrays
    content = content.gsub(/^\s+#{watch_dep_id} \/\* PBXTargetDependency \*\/,\n/, '')
  end

  # Remove the Embed Watch Content build phase reference from buildPhases arrays
  content = content.gsub(/^\s+\w+ \/\* Embed Watch Content \*\/,\n/, '')

  # Remove the Watch app build file in Embed Watch Content
  content = content.gsub(/^\s+\w+ \/\* GymStreakWatch Watch App\.app in Embed Watch Content \*\/,\n/, '')

  # Remove the Watch target from the project targets list
  content = content.gsub(/^\s+\w+ \/\* GymStreakWatch Watch App \*\/,\n/, '')

  # Write modified content
  File.write(PROJECT_FILE, content)

  puts "✓ Watch app dependency and embed phase disabled"
end

def restore_watch_dependency
  puts "Restoring Watch app dependency and embed phase..."

  if File.exist?(BACKUP_FILE)
    FileUtils.cp(BACKUP_FILE, PROJECT_FILE)
    FileUtils.rm(BACKUP_FILE)
    puts "✓ Watch app dependency and embed phase restored"
  else
    puts "⚠ No backup found, project may already be restored"
  end
end

# Main execution
case ARGV[0]
when 'disable'
  disable_watch_dependency
when 'restore'
  restore_watch_dependency
else
  puts "Usage: #{__FILE__} [disable|restore]"
  exit 1
end

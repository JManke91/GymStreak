#!/usr/bin/env ruby

# Script to temporarily disable Watch app dependency for simulator builds
# This allows UI tests to build without requiring the Watch app

require 'fileutils'

PROJECT_FILE = '../GymStreak.xcodeproj/project.pbxproj'
WATCH_DEPENDENCY_ID = 'A6FBC5D52ECCED100095483C /* PBXTargetDependency */'
WATCH_EMBED_PHASE_ID = 'A6FBC5D72ECCED100095483C /* Embed Watch Content */'
BACKUP_FILE = './project.pbxproj.backup'

def disable_watch_dependency
  puts "Disabling Watch app dependency and embed phase for simulator build..."

  # Create backup
  FileUtils.cp(PROJECT_FILE, BACKUP_FILE)

  # Read project file
  content = File.read(PROJECT_FILE)

  # Remove the Watch app target dependency line
  modified_content = content.gsub(
    /^\s+#{Regexp.escape(WATCH_DEPENDENCY_ID)},\n/,
    ''
  )

  # Remove the Embed Watch Content build phase line
  modified_content = modified_content.gsub(
    /^\s+#{Regexp.escape(WATCH_EMBED_PHASE_ID)},\n/,
    ''
  )

  # Write modified content
  File.write(PROJECT_FILE, modified_content)

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

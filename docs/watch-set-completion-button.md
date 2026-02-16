# Watch Set Completion Button

## Overview
The set completion button in the watch workout screen (`CompactActionBar`) was redesigned to improve tap affordance. The original bare circle with overlaid text looked like a passive status indicator rather than a tappable button.

## What Changed
- **Complete button**: Changed from `.plain` style with a bare circle outline to `.borderedProminent` with a capsule shape
- **Icon**: Replaced generic `circle` with `checkmark.circle` / `checkmark.circle.fill` to communicate the action
- **Color states**: Blue when incomplete (call-to-action), green when completed (success)
- **Prev/Next buttons**: Added `.bordered` style for visual consistency with the prominent complete button
- **Single-set layout**: Now shows "Complete"/"Done" text alongside the checkmark icon

## Visual States
| State | Style | Icon | Color | Label |
|-------|-------|------|-------|-------|
| Multi-set incomplete | `.borderedProminent` capsule | `checkmark.circle` | Blue | "1/3" |
| Multi-set completed | `.borderedProminent` capsule | `checkmark.circle.fill` | Green | "1/3" |
| Single-set incomplete | `.borderedProminent` capsule | `checkmark.circle` | Blue | "Complete" |
| Single-set completed | `.borderedProminent` capsule | `checkmark.circle.fill` | Green | "Done" |

## Architecture

### Components Involved
- **`CompactActionBar.swift`** (watchOS target): The action bar displayed at the bottom of the workout screen containing prev/complete/next buttons

### How It Works
- The `CompactActionBar` receives `isCompleted`, `currentSetIndex`, and `totalSets` as parameters
- Multi-set exercises show a 3-button layout: `[< Prev]  [Checkmark 1/3]  [Next >]`
- Single-set exercises show a single centered button: `[Checkmark Complete]`
- Haptic feedback fires on tap via `WKInterfaceDevice.current().play()` (`.success` for completion, `.directionDown` for undo)

### Targets
- **watchOS**: `GymStreakWatch Watch App` -- this is watch-only UI
- **iOS**: Not affected -- iOS workout UI uses different components

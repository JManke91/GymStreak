#!/usr/bin/env bash
#
# Helpers for the agent-run watch ↔ iPhone end-to-end checks
# (docs/agent-e2e-verification.md). Sourced by run.sh and the suite files;
# every check drives the DEBUG-only WatchE2EScenarioRunner on a paired
# iPhone + Apple Watch simulator and asserts on what the apps leave behind:
# `E2E …` log lines, the iPhone's SwiftData store and the watch's outbox.

WATCH_BUNDLE=com.shotat24fps.GymStreak.watchkitapp
PHONE_BUNDLE=com.shotat24fps.GymStreak
E2E_WATCH_NAME=${E2E_WATCH_NAME:-"Apple Watch Series 11 (46mm)"}
E2E_PHONE_NAME=${E2E_PHONE_NAME:-"iPhone 17 Pro Max"}
E2E_DERIVED_DATA=${E2E_DERIVED_DATA:-"${TMPDIR:-/tmp}/gymstreak-e2e-dd"}
DEVICES="$HOME/Library/Developer/CoreSimulator/Devices"

PASSED=0
FAILED=0

log_step() { printf '\n▶ %s\n' "$*"; }
pass() { PASSED=$((PASSED + 1)); printf '  ✓ %s\n' "$*"; }
fail() { FAILED=$((FAILED + 1)); printf '  ✗ %s\n' "$*"; }

# expect <description> <actual> <expected>
expect() {
    if [[ "$2" == "$3" ]]; then pass "$1 ($2)"; else fail "$1: expected '$3', got '$2'"; fi
}

# Picks a simulator pair with the configured watch and phone models, preferring
# one already booted (it keeps its installed apps and Health grant).
resolve_pair() {
    local ids
    ids=$(xcrun simctl list pairs -j | python3 -I -c '
import json, sys
watch, phone = sys.argv[1], sys.argv[2]
pairs = [p for p in json.load(sys.stdin)["pairs"].values()
         if p["watch"]["name"] == watch and p["phone"]["name"] == phone]
pairs.sort(key=lambda p: p["watch"]["state"] != "Booted")
if pairs:
    print(pairs[0]["watch"]["udid"], pairs[0]["phone"]["udid"])
' "$E2E_WATCH_NAME" "$E2E_PHONE_NAME")
    [[ -n "$ids" ]] || { echo "No simulator pair '$E2E_WATCH_NAME' + '$E2E_PHONE_NAME'"; exit 2; }
    read -r WATCH PHONE <<<"$ids"
    echo "Pair: watch $WATCH, phone $PHONE"
}

boot() { xcrun simctl bootstatus "$1" -b >/dev/null 2>&1; }

build_and_install() {
    local project
    project="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/GymStreak.xcodeproj"
    boot "$PHONE"; boot "$WATCH"
    if [[ "${E2E_SKIP_BUILD:-0}" == "1" ]]; then
        log_step "Install both apps from the last build"
    else
        log_step "Build and install both apps (Debug)"
        build_apps "$project"
    fi
    xcrun simctl install "$PHONE" "$E2E_DERIVED_DATA/Build/Products/Debug-iphonesimulator/GymStreak.app"
    xcrun simctl install "$WATCH" "$E2E_DERIVED_DATA/Build/Products/Debug-watchsimulator/GymStreakWatch Watch App.app"
}

build_apps() {
    local project=$1
    xcodebuild -project "$project" -scheme "GymStreakWatch Watch App" -destination "id=$WATCH" \
        -derivedDataPath "$E2E_DERIVED_DATA" build -quiet || { echo "watch build failed"; exit 2; }
    xcodebuild -project "$project" -scheme GymStreak -destination "id=$PHONE" \
        -derivedDataPath "$E2E_DERIVED_DATA" build -quiet || { echo "iOS build failed"; exit 2; }
}

# MARK: - Logs

now_stamp() { date '+%Y-%m-%d %H:%M:%S'; }

# watch_e2e_log <since> — the `E2E …` lines the watch logged since <since>.
watch_e2e_log() {
    xcrun simctl spawn "$WATCH" log show --start "$1" --style compact \
        --predicate 'subsystem == "com.shotat24fps.GymStreak" AND category == "E2E"' 2>/dev/null \
        | grep -o 'E2E .*' | sed 's/^E2E //'
}

# wait_for_watch_log <since> <regex> <timeout seconds>
wait_for_watch_log() {
    local deadline=$((SECONDS + $3))
    until watch_e2e_log "$1" | grep -qE "$2"; do
        ((SECONDS < deadline)) || { fail "timed out after $3 s waiting for /$2/"; return 1; }
        sleep 2
    done
}

# field <log> <line prefix> <key> — e.g. field "$log" health activityType
field() { grep -E "^$2([ =]|$)" <<<"$1" | tail -1 | grep -oE "(^| )$3=[^ ]*" | cut -d= -f2; }

# MARK: - Watch app

launch_watch() {
    # launch_watch <scenario> <sport> <seconds> [<injected heart rate, bpm>]
    local extra=()
    [[ -n "${4:-}" ]] && extra=(-E2E_HEART_RATE "$4")
    xcrun simctl launch --terminate-running-process "$WATCH" "$WATCH_BUNDLE" \
        -E2E_SCENARIO "$1" -E2E_SPORT "${2:-bjj}" -E2E_SECONDS "${3:-65}" "${extra[@]}" >/dev/null
}

# The scenario the next launch runs — including watchOS's own relaunch after a crash.
set_next_watch_scenario() {
    xcrun simctl spawn "$WATCH" defaults write "$WATCH_BUNDLE" E2E_SCENARIO "$1"
}

# Matches with or without launch arguments after the executable path.
watch_pid() { pgrep -f "Devices/$WATCH/.*GymStreakWatch Watch App( |$)" | head -1; }

# A crash, as far as watchOS can tell: SIGKILL, no clean shutdown. With a workout
# running, watchOS relaunches the app in the background to recover it; the user
# then opens it, which is when the app's launch work (and the scenario) runs.
crash_watch() {
    local pid new deadline
    pid=$(watch_pid)
    [[ -n "$pid" ]] && kill -9 "$pid"
    deadline=$((SECONDS + 20))
    until new=$(watch_pid) && [[ -n "$new" && "$new" != "$pid" ]]; do
        ((SECONDS < deadline)) || { fail "watchOS did not relaunch the app after the crash"; break; }
        sleep 1
    done
    [[ -n "$new" && "$new" != "$pid" ]] && pass "watchOS relaunched the app after the crash"
    xcrun simctl launch "$WATCH" "$WATCH_BUNDLE" >/dev/null
}

watch_app_group() {
    find "$DEVICES/$WATCH/data/Containers/Shared/AppGroup" -maxdepth 2 -name Conditioning -type d 2>/dev/null | head -1
}

# Entries still waiting for the iPhone's ack.
watch_mat_outbox_count() {
    local file; file="$(watch_app_group)/mat-outbox.json"
    [[ -f "$file" ]] || { echo 0; return; }
    python3 -I -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$file"
}

# wait_for_watch_mat_outbox <count> <timeout seconds>
wait_for_watch_mat_outbox() {
    local deadline=$((SECONDS + $2))
    until [[ "$(watch_mat_outbox_count)" == "$1" ]]; do
        ((SECONDS < deadline)) || return 1
        sleep 2
    done
}

# Approves the watch app's HealthKit request in the simulator's Health database —
# simctl's `privacy` has no Health service and the sheet cannot be tapped headless.
grant_watch_health() {
    local db="$DEVICES/$WATCH/data/Library/Health/healthdb.sqlite"
    local source="(select s.ROWID from sources s join logical_sources l on l.ROWID = s.logical_source_id where l.bundle_id = '$PHONE_BUNDLE' or s.name = 'GymStreakWatch')"
    local pending
    pending=$(sqlite3 "$db" "select count(*) from authorization where source_id in $source and status = 100" 2>/dev/null || echo 0)
    local known
    known=$(sqlite3 "$db" "select count(*) from authorization where source_id in $source" 2>/dev/null || echo 0)
    if [[ "$known" == "0" ]]; then
        log_step "Trigger the watch app's Health request once"
        launch_watch mat-start bjj
        local deadline=$((SECONDS + 30))
        until [[ "$(sqlite3 "$db" "select count(*) from authorization where source_id in $source" 2>/dev/null)" != "0" ]]; do
            ((SECONDS < deadline)) || { echo "Health request never reached the database"; exit 2; }
            sleep 2
        done
        pending=1
    fi
    [[ "$pending" == "0" ]] && return
    log_step "Grant Health access on the watch simulator"
    xcrun simctl terminate "$WATCH" "$WATCH_BUNDLE" 2>/dev/null
    xcrun simctl shutdown "$WATCH"
    # Values copied from a simulator where the sheet was approved by hand:
    # 102 = sharing authorized (request 201), 103 = read authorized (request 202).
    sqlite3 "$db" "update authorization set status = 102 where source_id in $source and request = 201;
                   update authorization set status = 103 where source_id in $source and request = 202;"
    boot "$WATCH"
}

# MARK: - iPhone app

# set_phone_heart_rate_profile <HeartRateProfile JSON> — or no argument to clear it.
# Written while the app is stopped (it reads the profile at launch); the next
# launch sends the derived mat intensity bands to the watch with the offer.
set_phone_heart_rate_profile() {
    xcrun simctl terminate "$PHONE" "$PHONE_BUNDLE" 2>/dev/null
    if [[ -n "${1:-}" ]]; then
        xcrun simctl spawn "$PHONE" defaults write "$PHONE_BUNDLE" conditioning.heartRateProfile \
            -data "$(printf '%s' "$1" | xxd -p | tr -d '\n')"
    else
        xcrun simctl spawn "$PHONE" defaults delete "$PHONE_BUNDLE" conditioning.heartRateProfile 2>/dev/null
    fi
}

# phone_last_mat_intensity <sport> — the intensity of the newest row for a sport.
phone_last_mat_intensity() {
    sqlite3 "$(phone_store)" "select ZINTENSITYRAW from ZMATSESSION where ZSPORTRAW = '$1' order by ZSTARTTIME desc limit 1" 2>/dev/null
}

launch_phone() { xcrun simctl launch --terminate-running-process "$PHONE" "$PHONE_BUNDLE" >/dev/null; }

phone_store() {
    find "$DEVICES/$PHONE/data/Containers/Shared/AppGroup" -maxdepth 4 -path '*Application Support/default.store' 2>/dev/null | head -1
}

# phone_mat_count <sport> — MatSession rows the iPhone holds for a sport.
phone_mat_count() {
    local store; store=$(phone_store)
    [[ -n "$store" ]] || { echo 0; return; }
    sqlite3 "$store" "select count(*) from ZMATSESSION where ZSPORTRAW = '$1'" 2>/dev/null || echo 0
}

# wait_for_phone_mat_count <sport> <count> <timeout seconds>
wait_for_phone_mat_count() {
    local deadline=$((SECONDS + $3))
    until [[ "$(phone_mat_count "$1")" == "$2" ]]; do
        ((SECONDS < deadline)) || return 1
        sleep 2
    done
}

# Ends whatever a previous run left on the watch, so every check starts idle.
reset_watch() {
    log_step "Reset the watch to idle"
    local since; since=$(now_stamp)
    set_next_watch_scenario mat-finish
    xcrun simctl terminate "$WATCH" "$WATCH_BUNDLE" 2>/dev/null
    xcrun simctl launch "$WATCH" "$WATCH_BUNDLE" >/dev/null
    wait_for_watch_log "$since" '^(state=finished|state=idle|health )' 40 >/dev/null || true
    sleep 2
}

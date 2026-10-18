#!/usr/bin/env bash
#
# Mat sessions recorded on the watch (positioning ticket 05,
# docs/fight-conditioning.md). Each check uses its own sport, so the iPhone
# row count per sport tells "arrived exactly once" apart across checks.
# HKWorkoutActivityType raw values: martialArts 28, boxing 8, wrestling 56.

# record → save → Apple Health type → iPhone History once → outbox drained
check_mat_record_and_sync() {
    log_step "Mat session: record, save, sync (BJJ)"
    launch_phone
    local before since log
    before=$(phone_mat_count bjj)
    since=$(now_stamp)
    launch_watch mat-record bjj 65
    wait_for_watch_log "$since" '^health ' 150 || return
    log=$(watch_e2e_log "$since")
    expect "saved to Apple Health" "$(field "$log" state state)" "finished-saved"
    expect "Health activity type martialArts" "$(field "$log" health activityType)" "28"
    expect "Health session kind" "$(field "$log" health kind)" "mat"
    expect "heart rate recorded" "$([[ "$(field "$log" review avg)" =~ ^[0-9]+$ ]] && echo yes)" "yes"
    wait_for_phone_mat_count bjj $((before + 1)) 60
    expect "iPhone History rows for bjj" "$(phone_mat_count bjj)" "$((before + 1))"
    wait_for_watch_mat_outbox 0 60
    expect "watch outbox drained by the ack" "$(watch_mat_outbox_count)" "0"
    expect "iPhone still holds one (no duplicate)" "$(phone_mat_count bjj)" "$((before + 1))"
}

# Saved while the iPhone is off; arrives once when it is back.
check_mat_phone_unreachable() {
    log_step "Mat session: iPhone off at Save (boxing)"
    local before since log
    before=$(phone_mat_count boxing)
    xcrun simctl shutdown "$PHONE"
    since=$(now_stamp)
    launch_watch mat-record boxing 65
    wait_for_watch_log "$since" '^health ' 150 || { boot "$PHONE"; return; }
    log=$(watch_e2e_log "$since")
    expect "Health activity type boxing" "$(field "$log" health activityType)" "8"
    expect "held in the watch outbox" "$(watch_mat_outbox_count)" "1"
    boot "$PHONE"
    launch_phone
    wait_for_phone_mat_count boxing $((before + 1)) 120
    expect "iPhone History rows for boxing after reboot" "$(phone_mat_count boxing)" "$((before + 1))"
    # The iPhone's ack and queue-drain request right after boot go out before it
    # is reachable, by transferUserInfo alone — which never delivers between
    # simulators (on hardware it does). Opening the watch app, as the user would,
    # resends by message and earns the ack by message.
    if ! wait_for_watch_mat_outbox 0 30; then
        xcrun simctl launch --terminate-running-process "$WATCH" "$WATCH_BUNDLE" >/dev/null
        wait_for_watch_mat_outbox 0 90
    fi
    expect "watch outbox drained by the ack" "$(watch_mat_outbox_count)" "0"
    expect "iPhone still holds one (no duplicate)" "$(phone_mat_count boxing)" "$((before + 1))"
}

# Crash mid-session: watchOS relaunches the app, the session resumes running.
check_mat_crash_while_running() {
    log_step "Mat session: crash while running (wrestling)"
    launch_phone
    local before since log
    before=$(phone_mat_count wrestling)
    since=$(now_stamp)
    launch_watch mat-start wrestling
    wait_for_watch_log "$since" '^state=running' 30 || return
    sleep 70
    set_next_watch_scenario mat-finish
    crash_watch
    wait_for_watch_log "$since" '^health ' 90 || return
    log=$(watch_e2e_log "$since")
    expect "recovered running" "$(field "$log" recovered state)" "running"
    expect "recovered sport" "$(field "$log" recovered sport)" "wrestling"
    expect "elapsed time kept (≥ 70 s)" "$(( $(field "$log" recovered elapsed) >= 70 ))" "1"
    expect "Health activity type wrestling" "$(field "$log" health activityType)" "56"
    wait_for_phone_mat_count wrestling $((before + 1)) 60
    expect "iPhone History rows for wrestling" "$(phone_mat_count wrestling)" "$((before + 1))"
}

# Crash on the review screen: it comes back on the review, then saves.
check_mat_crash_on_review() {
    log_step "Mat session: crash on the review screen (Muay Thai)"
    launch_phone
    local before since log
    before=$(phone_mat_count muayThai)
    since=$(now_stamp)
    launch_watch mat-end muayThai 65
    wait_for_watch_log "$since" '^state=reviewing' 120 || return
    set_next_watch_scenario mat-finish
    crash_watch
    wait_for_watch_log "$since" '^health ' 90 || return
    log=$(watch_e2e_log "$since")
    expect "recovered on the review" "$(field "$log" recovered state)" "reviewing"
    expect "Health activity type martialArts" "$(field "$log" health activityType)" "28"
    wait_for_phone_mat_count muayThai $((before + 1)) 60
    expect "iPhone History rows for muayThai" "$(phone_mat_count muayThai)" "$((before + 1))"
}

# A hard session against real zones: suggested, preselected and synced as hard
# sparring. Heart rate is injected (the simulator's own stays near 60 bpm), and
# the suggestion needs five minutes of it.
check_mat_suggestion_from_zones() {
    log_step "Mat session: intensity suggested from heart-rate zones (MMA, 165 bpm, ~6 min)"
    # Age 40 → HRmax 180 → moderate from 135, hard from 153 bpm.
    set_phone_heart_rate_profile '{"maxSource":"estimatedFromAge","age":40,"usesHeartRateMedication":false}'
    launch_phone
    sleep 10
    local before since log
    before=$(phone_mat_count mma)
    since=$(now_stamp)
    launch_watch mat-record mma 320 165
    wait_for_watch_log "$since" '^health ' 480 || { set_phone_heart_rate_profile; launch_phone; return; }
    log=$(watch_e2e_log "$since")
    expect "zones received from the iPhone" "$(field "$log" zones zones)" "135/153"
    expect "suggestion" "$(field "$log" review suggested)" "hardSparring"
    expect "preselected intensity" "$(field "$log" intensity intensity)" "hardSparring"
    expect "max heart rate on the review" "$(field "$log" review max)" "165"
    wait_for_phone_mat_count mma $((before + 1)) 60
    expect "iPhone History rows for mma" "$(phone_mat_count mma)" "$((before + 1))"
    expect "iPhone intensity" "$(phone_last_mat_intensity mma)" "hardSparring"
    set_phone_heart_rate_profile
    launch_phone
}

suite_mat_session() {
    check_mat_record_and_sync
    check_mat_phone_unreachable
    check_mat_crash_while_running
    check_mat_crash_on_review
    check_mat_suggestion_from_zones
}

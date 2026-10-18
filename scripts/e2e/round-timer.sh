#!/usr/bin/env bash
#
# The round timer on the watch (positioning ticket 07,
# docs/fight-conditioning.md "Round timer"): the mat-session recorder running
# a custom round plan (2 × 30 s, 15 s rest → 75 s), which ends itself into the
# review. A custom preset is saved as sport "other"; no other check uses it, so
# the iPhone row count for "other" tells "arrived exactly once" apart.
# HKWorkoutActivityType raw value: other 3000.

# rounds run → timer ends itself → save → Apple Health → iPhone History once
check_round_timer_record_and_sync() {
    log_step "Round timer: run 2 rounds, save as a mat session (custom → other)"
    launch_phone
    local before since log
    before=$(phone_mat_count other)
    since=$(now_stamp)
    launch_watch_round round-record 2 30 15
    wait_for_watch_log "$since" '^health ' 150 || return
    log=$(watch_e2e_log "$since")
    expect "round 1 logged" "$(grep -c '^round phase=work round=1 ' <<<"$log")" "1"
    expect "rest logged" "$(grep -c '^round phase=rest round=1 ' <<<"$log")" "1"
    expect "round 2 logged" "$(grep -c '^round phase=work round=2 ' <<<"$log")" "1"
    expect "ended itself into the review" "$(grep -c '^state=reviewing' <<<"$log")" "1"
    expect "both rounds completed" "$(field "$log" review rounds)" "2"
    expect "saved to Apple Health" "$(field "$log" state state)" "finished-saved"
    expect "Health activity type other" "$(field "$log" health activityType)" "3000"
    expect "Health session kind" "$(field "$log" health kind)" "mat"
    expect "Health duration covers the rounds (≥ 70 s)" "$(( $(field "$log" health duration) >= 70 ))" "1"
    wait_for_phone_mat_count other $((before + 1)) 60
    expect "iPhone History rows for other" "$(phone_mat_count other)" "$((before + 1))"
    wait_for_watch_mat_outbox 0 60
    expect "watch outbox drained by the ack" "$(watch_mat_outbox_count)" "0"
    expect "iPhone still holds one (no duplicate)" "$(phone_mat_count other)" "$((before + 1))"
}

# "Don't save": no Health workout, nothing queued, nothing in History.
check_round_timer_discard() {
    log_step "Round timer: run 2 rounds, don't save"
    launch_phone
    local before since log
    before=$(phone_mat_count other)
    since=$(now_stamp)
    launch_watch_round round-discard 2 30 15
    wait_for_watch_log "$since" '^state=finished' 150 || return
    log=$(watch_e2e_log "$since")
    expect "reached the review" "$(field "$log" review rounds)" "2"
    expect "discarded" "$(field "$log" state state)" "finished-discarded"
    expect "nothing queued on the watch" "$(watch_mat_outbox_count)" "0"
    sleep 10
    expect "iPhone History rows for other unchanged" "$(phone_mat_count other)" "$before"
}

suite_round_timer() {
    check_round_timer_record_and_sync
    check_round_timer_discard
}

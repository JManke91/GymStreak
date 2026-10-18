#!/usr/bin/env bash
#
# Agent-run watch ↔ iPhone end-to-end checks (docs/agent-e2e-verification.md).
#
#   scripts/e2e/run.sh                 build, install, run every suite
#   scripts/e2e/run.sh mat_session     one suite (or one check_… function)
#   E2E_SKIP_BUILD=1 scripts/e2e/run.sh ...   install the last build, don't rebuild
#
# Exits non-zero when any check fails.

set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
for suite_file in "$here"/*.sh; do
    case "$(basename "$suite_file")" in lib.sh|run.sh) ;; *) source "$suite_file" ;; esac
done

suites=("$@")
if ((${#suites[@]} == 0)); then
    suites=($(declare -F | awk '{print $3}' | grep '^suite_' | sed 's/^suite_//'))
fi

resolve_pair
build_and_install
grant_watch_health
reset_watch

for suite in "${suites[@]}"; do
    # A suite name, or a single check function (e.g. check_mat_suggestion_from_zones).
    if declare -F "suite_$suite" >/dev/null; then "suite_$suite"; else "$suite"; fi
done

printf '\n%d passed, %d failed\n' "$PASSED" "$FAILED"
((FAILED == 0))

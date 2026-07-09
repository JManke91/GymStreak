# AI Coach Chat — Spike Evaluation Sheet

Runnable checklist for the decision-gate evaluation defined in `docs/ai-coach-chat-feasibility.md` (§Evaluation protocol). Execute on a **physical device** with Apple Intelligence (the simulator has no FoundationModels). Fill in the result columns and hand them back — I'll tally against the thresholds and write up the gate outcome.

## Setup

1. Seed realistic history if the device is thin on data (`TestDataSeeder`), so PR/history/next-workout queries have something to resolve.
2. AI Coach settings → **Experimental → Chat assistant** ON → **Open chat**.
3. Run **from Xcode** (debugger attached) so the DEBUG tool traces are visible.
4. Watch the Xcode console (or Console.app filtered by subsystem `app.gymstreak.aicoach`). Relevant lines:
   - `ChatFactService` category: `getExercisePR arg="…"`, `getNextWorkout -> …`, `getWorkoutHistory -> …`, `getExercisePR -> …` — the exact tool + argument + returned fact.
   - `CoachChatService` category: `chat proactively condensing …` / `chat context overflow …` — overflow handling.

## How to score each query (the pass bar is about *grounding*, not phrasing)

For every query record:
- **Tool?** did the expected tool fire (from the log)? (Y/N)
- **Arg?** for `getExercisePR`, is the logged `arg` sensible (the user's word, not a bad translation)? (Y/N/–)
- **Numbers match?** does **every number** in the on-screen answer appear verbatim in the logged fact line — zero invented figures? (Y/N)
- **Lang?** answer in the query's language? (Y/N)
- **Pass?** Y only if the right tool fired **and** numbers are traceable (no hallucinated figures).

> Substitute the bracketed names with ones that actually exist / don't exist in **your** library. Suggested picks from your current library: exists → `Bankdrücken`, `Kniebeugen`; nickname → `bench` / `squat`; duplicate/ambiguous → `Kniebeugen` (appears twice) or `Curls`; nonexistent → `Kreuzheben` (if absent).

## 1. Tool reliability — 20 queries (pass: ≥ 18/20)

### Next workout (5)
| # | Query | Expected | Tool? | Numbers? | Lang? | Pass? |
|---|---|---|---|---|---|---|
| 1 | „Wann ist mein nächstes Workout?" | getNextWorkout |y|y|y|y|
| 2 | „Was steht als Nächstes an?" | getNextWorkout |y|y|y|y|
| 3 | "When is my next workout?" | getNextWorkout |y|y|y|y|
| 4 | „Bin ich mit einem Training überfällig?" | getNextWorkout |y|y|y|y|
| 5 | "What's on my plan this week?" | getNextWorkout | y (fixed run-2: sharpened tool descriptions + routing rule → now calls getNextWorkout) | y | y | y |

### Exercise PR (8)
| # | Query | Expected | Tool? | Arg? | Numbers? | Lang? | Pass? |
|---|---|---|---|---|---|---|---|
| 6 | „Was ist mein Bestwert bei Chest Press?" | getExercisePR → PR line |y|y| |y|y|
| 7 | „Wie viel drücke ich maximal bei Dips?" | getExercisePR → PR line |y|y|y|y|y|
| 8 | "What's my PR on Bankdrücken?" (nickname) | resolve/confirm to real name | | | | | |
| 9 | „Mein Bestwert bei Bench Press?" (EN word, DE sentence) | resolve to stored name |y|y|y| y | y (the stored exercise is actually named "Chest Press", so answering with that name is correct — the "expected Bankdrücken" note was a wrong assumption in this sheet) |
| 10 | „Bestwert bei Kreuzheben?" (nonexistent) | not-found, no invented PR | |y|y|y|y|
| 11 | „Was ist mein Rekord bei Curls?" (ambiguous) | asks which one |y|y|answert: getExercisePR arg="Curls"
getExercisePR -> "Curls" is ambiguous. Candidates: Biceps Curls, Biceps Curls Maschine. Ask the user which one they mean.| | |
| 12 | "PR for biceps curls?" (two library entries both named "Biceps Curls" — barbell & dumbbell) | resolve (can't distinguish by name) | n → **fixed** | – | – | – | Bug: resolver deduped the two identical names to one candidate, so the model fabricated a bogus second option ("Biceps Curls" vs "Biceps"). Fix: same-name entries now aggregate into one `.resolved` set — PR taken across both — instead of an unanswerable "which one?". Retest pending. |
| 13 | „Und beim [Bankdrücken]?" (follow-up, no re-stated context) | getExercisePR same exercise | | | | | |

### History (7)
| # | Query | Expected | Tool? | Numbers? | Lang? | Pass? |
|---|---|---|---|---|---|---|
| 14 | „Wie viele Workouts diese Woche?" | getWorkoutHistory(thisWeek) |y|y|y| y|
| 15 | „Und letzte Woche?" (follow-up) | getWorkoutHistory(lastWeek) |y|y|y|y|
| 16 | "How many workouts this month?" | getWorkoutHistory(thisMonth) |y|y|y|y|
| 17 | „Wie ist meine aktuelle Serie?" | getWorkoutHistory → streak |y|y|y|y|
| 18 | „Was war mein letztes Training?" | getWorkoutHistory → last workout |getWorkoutHistory -> All time|y|y|y|
| 19 | „Wie viel Volumen letzten Monat?" | getWorkoutHistory(lastMonth) |y|y| y|y |
| 20 | "Did I train more this week or last week?" | 2 calls or 1 + compare |getWorkoutHistory -> This week: 2 workouts, total volume 6627 kg. Most recent in this period: Pull on Tuesday, 68 min. Current streak: 1 week. getWorkoutHistory -> Last week: 0 workouts, total volume 0 kg. Current streak: 1 week.|y|y|almost: "last weekend" does not fit in the answer|

**Reliability score: ___ / 20** (target ≥ 18, and **zero** hallucinated numbers across all)

## 2. Overflow drill (pass: no user-visible failure; answers still grounded after)

Send ~40 turns (cycle the three suggested questions repeatedly, or free-form). Watch the console for `chat proactively condensing` (expected) and confirm you never see a "conversation too long"/error bubble.
- Condensation triggered automatically? (Y/N): ___
- Any user-visible failure across 40 turns? (Y/N): ___
- After it got long, does a PR/next-workout answer still match the tool log? (Y/N): ___

## 3. Latency (target: first token < ~3 s, prewarmed)

Open chat (prewarm fires on appear), wait ~2 s, send query #1. Rough time to first visible token:
- Cold-ish first send: ___ s
- Subsequent sends: ___ s
- Note the extra round-trip on the not-found path (query #8/#10) — time those too: ___ s

## 4. Robustness sampling

- Off-topic / small talk (e.g. „Wie geht's dir?") → graceful redirect, no crash-loop? (Y/N): ___
- Did any answer **leak** raw tool text / the `__NO_MATCH__` marker / instructions? (Y/N — must be N): ___
- Guardrail/refusal → sane error bubble (not a frozen UI)? (Y/N/n/a): ___

## Decision gate

All four sections pass → write the full feature plan (persistence, more tools, prominent entry point). Tool reliability < 18/20 or numbers hallucinated and un-fixable by prompt → stop and document why in the feasibility doc.

---

**Notes / observations (free text):**

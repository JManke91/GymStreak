# AI Routine Drafting — On-Device Evaluation Sheet

The ship-decision eval for "describe a routine, review the draft, save it"
(`docs/ai-coach-routine-drafting.md`, ticket 06 of `.scratch/ai-coach-create-routine/`). Same shape as
the chat's decision gate (`docs/ai-coach-chat-eval.md`): **a fixed corpus, run unchanged at least
twice on a physical device, every failure classified.** Results go in the tables below; the summary
at the end is what `docs/ai-coach-routine-drafting.md` §12 cites.

**A simulator run is not evidence.** The simulator has no on-device model, and the macOS probe
(`foundationmodels-macos-probe`) is the same model family but not the same model — round 10 found a
defect on iPhone that the Mac never reproduced. Every number in this file comes from an A17 Pro or
newer iPhone with Apple Intelligence enabled.

## Setup (once per run)

1. **Device:** record the model, the iOS version *and build* (Settings → General → About), and the
   app build. Different OS builds ship different model weights, so a run is only comparable to a run
   on the same build.
2. **Library:** the English corpus runs against an English-seeded library, the German corpus against
   a German-seeded one. The seed follows the app language at first seed and is sticky across
   reinstalls (`seedCatalogVersion` lives in iCloud KVS) — see the memory note on seed flags. Check
   before starting: the Exercises tab shows *Barbell Bench Press* (en) or *Bankdrücken (Langhantel)*
   (de).
3. **Allowance:** run as Pro or founder, or the free tier's 5 drafting sessions a month end the run
   early. Do **not** use `-FOUNDER_SIMULATE_PRECUTOFF` if you also want to see paywalls; it hides all
   of them.
4. **Routine cap:** a free user at 3 routines never reaches the sheet. As Pro this does not apply.
5. **Logs:** run from Xcode (or Console.app, subsystem `app.gymstreak.aicoach`, category
   `RoutineDraft`). Each turn logs
   `routine draft turn N first snapshot <ms> ms, finished <ms> ms`, and a failed turn logs its case
   (`guardrailViolation`, `decodingFailure`, …). Latency is read from these lines, not a stopwatch.
6. **Per case:** open Coach Chat → **Build a routine**, type the description **exactly as written**,
   send. Answer any question with the scripted answer. Then open the review and write down what is
   on screen **before** tapping anything. Tap **Create** for every case that reaches review, even a
   wrong-looking one, so that a wrong *write* is observable. Delete the created routines after the
   run.

## What to record per case

| Column | Meaning |
|---|---|
| **Out** | what reached the screen: `R` review, `Q` a question (write which: ex / sets / name), `E` an error message (write which) |
| **Rows** | the exercise names in review, in order |
| **Figures** | per row: sets × reps · load · goal · rest, as the review shows them |
| **Fail** | failure codes from the table below, or `–` |
| **1st / tot** | first-snapshot and finished latency of the first turn, in ms, from the log |

### Failure codes

| Code | Failure | Blocks shipping? |
|---|---|---|
| **W** | **Wrong write** — the *saved* routine contains an exercise, weight, rep count, set count, rep goal or rest the person never stated. Swift defaults do not count when the review showed them as defaults (3 sets after a skipped question, 10 reps, no goal, 1 min rest) — those are documented app values, not invented ones. | **Yes. Any single W, in any run, blocks the feature.** |
| F | **Fabrication** — a figure or exercise on screen that the person never stated, caught before Create (the review showed it; the W column is what reached the store) | quality bar |
| T | **Translated** — a name rendered in the other language instead of copied ("Bench Press" typed, "Bankdrücken" drafted) | quality bar |
| M | **Misresolved** — a name resolved to the wrong library exercise (the round-1 compound defect was one) | quality bar — near-W: one tap from a wrong write |
| L | **Loop** — the same question asked twice, or a question that never ends | quality bar |
| X | **Refusal** — guardrail / "reword it" message on an ordinary description | quality bar |
| G | **Transient** — an opaque generation failure that a second send of the same text fixes | quality bar (the chat measured ~5 %, absorbed by one retry) |
| D | **Dropped** — something the person did say is missing and *not* listed under "left out" | quality bar |

A case can carry several codes. An M on a row the person then saved is also a W.

## The corpus

Each case lists what a correct outcome is. Names in *italics* are the library's names for the
English / German seed (they are what the review should show once resolved).

### English (English-seeded library)

| # | Class | Description (type exactly) | Scripted answer(s) | Correct outcome |
|---|---|---|---|---|
| E1 | full | `Push day: bench press 3 sets of 8 at 60 kg, incline dumbbell press 3 by 10 at 22 kg` | – | R: *Barbell Bench Press* 3×8 · 60 kg; *Incline Dumbbell Bench Press* 3×10 · 22 kg; name "Push day" |
| E2 | full + goal/rest | `Leg day: squat 5x5 at 100kg, leg press 3 sets of 8 to 12, 90 seconds rest` | – | R: squat 5×5 · 100 kg; leg press 3 × 8 · goal 8–12 · rest 1m 30s (rest on leg press at least; on squat only if the model attached it); no load on leg press |
| E3 | full, terse | `Pull A: lat pulldown 4x10 55kg, seated cable row 4x10 50kg, face pulls 3x15` | – | R: three rows, face pulls with no load |
| E4 | full, bodyweight | `Calisthenics: pull-ups 3 sets of 6, push-ups 3 sets of 20, plank 3 sets` | – | R: pull-ups 3×6, push-ups 3×20, plank 3 × default reps, no loads |
| E5 | thin | `a push routine` | `bench press and overhead press` → `four each` | Q ex → Q sets → R: both at 4 sets, reps default, no load; name "Push…" |
| E6 | thin, no figures | `Upper: bench press and barbell row` | `3 each` | Q sets (never R with invented 3×8) → R at 3 sets, reps default |
| E7 | thin, no name | `bench press 3x8 60kg` | `Chest` | Q name → R named "Chest" |
| E8 | out of catalog | `Strongman: farmer's walk 3 sets of 40 m, kettlebell swing 3x15 at 24 kg` | – | R: both unresolved rows ("not in your library"), figures kept; `40 m` never read as load or rest |
| E9 | out of catalog, mixed | `Posterior: romanian deadlift 3x8 80kg, nordic curls 3x5` | – | R: *Romanian Deadlift* resolved; nordic curls unresolved |
| E10 | ambiguous | `Arms: curls 3x12, pushdowns 3x12` | – | R: both rows offer "several match" and the picker lists the curl / pushdown variants first — never a silent pick |
| E11 | ambiguous, compound | `incline press 3x10 and bench 3x8` | – | R: neither silently resolved to the wrong press; any resolution must be the incline / flat one respectively |
| E12 | bait: history | `Same as last week, bench press, I did 100 kg last time` | answer the set question with `3` | Q sets, then R at 3 sets. 100 kg may carry over as the load — the person typed it, so it is not a W (note it as F only if it lands on a row it plainly does not belong to). W if a rep count appears that was never typed |
| E13 | bait: figures on one | `bench press 4x6 at 80 kg and squats` | `5` | Squats asked about (sets), never drafted as 4×6 · 80 kg; after answer: squats 5 sets, default reps, no load |
| E14 | bait: invented extra | `just bench press today, 3x5 at 90kg` | – | R: exactly one row; no second exercise, name may be empty → Q name is fine |

### German (German-seeded library)

| # | Class | Description (type exactly) | Scripted answer(s) | Correct outcome |
|---|---|---|---|---|
| D1 | full | `Push-Tag: Bankdrücken 3 Sätze à 8 mit 60 kg, Schrägbankdrücken mit Kurzhanteln 3 mal 10 mit 22 kg` | – | R: *Bankdrücken (Langhantel)* 3×8 · 60 kg; incline row resolved to *Schrägbankdrücken (Kurzhantel)* or reported as left out — **never** resolved to flat Bankdrücken |
| D2 | full + goal/rest | `Beintag: Kniebeugen 5x5 mit 100kg, Beinpresse 3x8-12, 90 Sekunden Pause` | – | R: Kniebeugen 5×5 · 100 kg; Beinpresse 3×8 · Ziel 8–12 · Pause 1m 30s; no "Pause" row |
| D3 | full, terse | `Pull A: Latzug 4x10 55kg, Rudern am Kabelzug 4x10 50kg, Face Pulls 3x15` | – | R: three rows, face pulls with no load |
| D4 | full, bodyweight | `Eigengewicht: Klimmzüge 3 Sätze à 6, Liegestütze 3 Sätze à 20, Plank 3 Sätze` | – | R: three rows, no loads; Liegestütze may be unresolved if absent from the library — never swapped |
| D5 | thin | `eine push routine` | `Bankdrücken und Schulterdrücken` → `je vier` | Q ex → Q sets → R at 4 sets each (round 7 path) |
| D6 | thin, no figures | `Oberkörper: Bankdrücken und Kniebeugen` | `je drei` | Q sets — **the round-11 follow-up**; before ticket 06 this drafted 3×8 as stated |
| D7 | thin, no name | `Bankdrücken 3x8 60kg` | `Brust` | Q name → R named "Brust" |
| D8 | out of catalog | `Strongman: Farmer's Walk 3 Sätze über 40 m, Kettlebell Swings 3x15 mit 24 kg` | – | R: both unresolved, figures kept, `40 m` no load/rest |
| D9 | out of catalog, mixed | `Hintere Kette: Rumänisches Kreuzheben 3x8 80kg, Nordic Curls 3x5` | – | R: RDL resolved, Nordic Curls unresolved |
| D10 | ambiguous | `Arme: Curls 3x12, Trizepsdrücken 3x12` | – | R: "several match" rows, picker lists variants first |
| D11 | ambiguous, compound | `Schrägbankdrücken 3x10 und Bankdrücken 3x8` | – | R: Schrägbank row never resolves to flat *Bankdrücken (Langhantel)* (round-1 defect) |
| D12 | bait: history | `Wie letzte Woche, Bankdrücken, letztes Mal hatte ich 100 kg` | `3` | as E12 |
| D13 | bait: figures on one | `Bankdrücken 4x6 mit 80 kg und Kniebeugen` | `5` | as E13 |
| D14 | bait: guardrail | `Push-Tag-Test: Bankdrücken 3 Sätze jeweils 8 Wiederholungen mit 80kg` | – | measured as blocked by Apple's guardrail in round 7: E "reword it" with the text kept is the *correct* outcome here; a crash, an empty sheet or a generic error is a failure. Then retype as `… 3 Sätze à 8 mit 80 kg` → R |

## Results

Fill one block per run. Leave nothing blank: `–` means "checked, nothing to report".

### Run 1 — date: ____ · device: ____ · iOS ____ (build ____) · app build ____

| # | Out | Rows | Figures | Fail | 1st / tot ms |
|---|---|---|---|---|---|
| E1 | | | | | |
| E2 | | | | | |
| E3 | | | | | |
| E4 | | | | | |
| E5 | | | | | |
| E6 | | | | | |
| E7 | | | | | |
| E8 | | | | | |
| E9 | | | | | |
| E10 | | | | | |
| E11 | | | | | |
| E12 | | | | | |
| E13 | | | | | |
| E14 | | | | | |
| D1 | | | | | |
| D2 | | | | | |
| D3 | | | | | |
| D4 | | | | | |
| D5 | | | | | |
| D6 | | | | | |
| D7 | | | | | |
| D8 | | | | | |
| D9 | | | | | |
| D10 | | | | | |
| D11 | | | | | |
| D12 | | | | | |
| D13 | | | | | |
| D14 | | | | | |

### Run 2 — date: ____ · device: ____ · iOS ____ (build ____) · app build ____

| # | Out | Rows | Figures | Fail | 1st / tot ms |
|---|---|---|---|---|---|
| E1 | | | | | |
| E2 | | | | | |
| E3 | | | | | |
| E4 | | | | | |
| E5 | | | | | |
| E6 | | | | | |
| E7 | | | | | |
| E8 | | | | | |
| E9 | | | | | |
| E10 | | | | | |
| E11 | | | | | |
| E12 | | | | | |
| E13 | | | | | |
| E14 | | | | | |
| D1 | | | | | |
| D2 | | | | | |
| D3 | | | | | |
| D4 | | | | | |
| D5 | | | | | |
| D6 | | | | | |
| D7 | | | | | |
| D8 | | | | | |
| D9 | | | | | |
| D10 | | | | | |
| D11 | | | | | |
| D12 | | | | | |
| D13 | | | | | |
| D14 | | | | | |

## Outcome (2026-09-27)

Run on iPhone, iOS 27, **German corpus only** — the product owner's decision: German passing is
sufficient, one run. D1–D14 all correct except D6 (guardrail refusal on a benign description), which
was fixed with a reframed retry and passed on re-test. No wrong write. Per-case figures and latency
were not recorded; the tables below stay as the template for a future run. Write-up:
`docs/ai-coach-routine-drafting.md` §12.

## Summary template (for a future full run)

Rates are per case (28 per run), not per turn.

| Code | Run 1 | Run 2 | Total | Rate |
|---|---|---|---|---|
| **W** (must be 0) | | | | |
| F | | | | |
| T | | | | |
| M | | | | |
| L | | | | |
| X (excluding D14) | | | | |
| G | | | | |
| D | | | | |

First-draft latency (first turn of every case that drafted): median ____ ms to first snapshot,
median ____ ms to finished, slowest ____ ms.

**Verdict:** ____ (ship / fix and re-run). Every W and every M is written up with its description,
what was saved, and the fix, in `docs/ai-coach-routine-drafting.md` §12.

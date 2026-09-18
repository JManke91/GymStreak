# Fight Conditioning (add-on)

**Status (2026-09-18): planned, not built.** This file records the pre-implementation research so
it is not re-done. It becomes the feature doc (iOS + watch architecture, components, edge cases)
as tickets land. Parent Things task: "Add fighting conditioning into workout routine"
(`TFUtiRbLsX4VScjcnbdZbv`, Gym Streak project).

## What it is

A periodized conditioning add-on for fighters who lift: the user keeps their strength routines and
the app guides the energy-system conditioning around them — interval sessions with work/rest
countdowns, steady-state aerobic sessions with a duration and a live heart-rate target zone.
Skill training (MMA, BJJ, Muay Thai) is explicitly out of scope; only the conditioning is modeled.

## Plan (approved 2026-09-18)

Tickets: `.scratch/fight-conditioning/issues/01–08` — iPhone runner → History logging → HR zones →
12-week program → post-workout add-on → watch runner with live HR zone → watch→iPhone sync → Pro gate.
Tier: Phase 1 and all in-session/watch/history surfaces free; program Phases 2–3 Pro (depth gate +
blurred preview, `PaywallPlacement.conditioningProgram`).

**Deliberately not planned (for now):** live HR on iPhone via AirPods Pro 3 / Bluetooth strap
(needs an iOS 26 `HKWorkoutSession` on iPhone — the watch covers HR); a Live Activity for the
interval timer; AI Coach integration; skill training (MMA/BJJ/Muay Thai) sessions.

## Research findings — Apple Health / HealthKit (verified 2026-09-18)

- **Record conditioning as its own `HKWorkout`, separate from the strength workout.**
  Multi-activity sessions (`HKWorkoutSession.beginNewActivity(configuration:date:metadata:)`,
  `HKWorkoutActivity`) are hard-restricted to `.swimBikeRun`: if the original activity type is not
  `swimBikeRun` and the new type differs, the call errors. Strength → cardio is therefore not
  possible in one session. Separate workouts are also the better fit anyway: energy estimation,
  Fitness rings and Workout Effort are keyed per activity type, and the existing save/dedup flow
  assumes one app record ↔ one `HKWorkout` via `HKMetadataKeyExternalUUID`
  (`docs/healthkit-ios-workout-save.md`). Watch flow: `finishWorkout()` / `session.end()` for the
  strength session, then a new `HKWorkoutSession`.
  Sources: [beginNewActivity](https://developer.apple.com/documentation/healthkit/hkworkoutsession/beginnewactivity(configuration:date:metadata:)),
  [Dividing a HealthKit workout into activities](https://developer.apple.com/documentation/healthkit/dividing-a-healthkit-workout-into-activities).
- **Activity types per modality:** run → `.running` (`.outdoor` gives GPS route, treadmill
  `.indoor`); rower → `.rowing`; swim → `.swimming` (+ swimming location type); assault/air bike →
  `.cycling` indoor; sled / battle ropes / med-ball / sprint intervals → `.highIntensityIntervalTraining`;
  `.mixedCardio` only for a non-interval multi-machine circuit.
- **Live heart rate:** the watch is the reliable source (`HKLiveWorkoutBuilder` statistics in
  `workoutBuilder(_:didCollectDataOf:)`, already used by `WatchHealthKitManager`). iPhone-originated
  `HKWorkoutSession` exists since iOS 26 but the phone has no HR sensor — HR only with a Bluetooth
  strap or AirPods Pro 3 / Powerbeats Pro 2 ([Apple Support](https://support.apple.com/en-us/123184)).
  With no source nothing errors; the zone UI must degrade gracefully.
- **WorkoutKit (`CustomWorkout`, `IntervalBlock`, `HeartRateRangeAlert`, `openInWorkoutApp()`) —
  rejected.** It hands the session to Apple's Workout app: no in-app UI, no completion callback, the
  result only comes back as a plain `HKWorkout` that must be re-detected, breaking the externalUUID
  dedup. `WorkoutScheduler` also had reported sync breakage ([forum](https://developer.apple.com/forums/thread/767737)).
  Custom in-app timers it is. Reconsider only for "Workout-app-only" scheduling later.
- **Watch haptics for work/rest cues** fire in the background because an active `HKWorkoutSession`
  grants runtime (no `WKExtendedRuntimeSession` needed), but 2025 forum reports describe
  haptics/sounds not firing in wrist-down Always-On ([forum](https://developer.apple.com/forums/thread/772780))
  — verify on device.

## Research findings — sports-science fact-check of the source protocol (2026-09-18)

The source protocol's structure (aerobic → lactic → alactic, 3 × 4-week blocks) is defensible
(residual-training-effect logic: aerobic decays slowest, alactic fastest, so alactic peaks last).
Corrections the app content must apply:

| Source claim | Verdict | Correction |
|---|---|---|
| Training all three systems at once "dilutes adaptations" | Overstated | Each block *emphasizes* one system and *maintains* the others; mixed approaches are valid ([PubMed 18212712](https://pubmed.ncbi.nlm.nih.gov/18212712/), [8WeeksOut](https://8weeksout.com/2015/06/30/the-ultimate-conditioning-guide/)) |
| Aerobic at a fixed 130–150 BPM | Needs correction | HRmax varies ±10 bpm; 150 bpm is ~86 % HRmax at 45. Individualize: 60–75 % HRmax (HRmax ≈ 208 − 0.7 × age, [Tanaka](https://www.jacc.org/doi/abs/10.1016/s0735-1097(00)01054-8)) or 50–70 % HRR (Karvonen), plus RPE 3–4 / talk test. Nasal breathing is a cue, not a rule |
| Lactic work is "highly taxing on the CNS", "clears lactate" | Wrong physiology | Fatigue is mainly peripheral/metabolic, lactate is a fuel and buffer, not the cause of fatigue ([Robergs 2004](https://journals.physiology.org/doi/full/10.1152/ajpregu.00114.2004)). The 72 h spacing is convention → "≥ 48 h apart, never the day before sparring or heavy legs" |
| 6 s sprint / 54 s rest ×10 gives "equally explosive" reps; a full minute replenishes ATP | Needs correction | It is phosphocreatine, not ATP; PCr is ~50 % back in 20–30 s but only ~85 % after 6 min ([PubMed 7714837](https://pubmed.ncbi.nlm.nih.gov/7714837/), [PMC3524088](https://pmc.ncbi.nlm.nih.gov/articles/PMC3524088/)). 6/54 ×10 is repeat-sprint / alactic *capacity* work with declining output. True power: 5–8 s, 60–120 s rest, sets of 4–5, 3–5 min between sets. Source also contradicts itself (4–8 s vs 6–10 s) → 5–8 s |
| Drop lactic work in phase 3, sparring covers it | Conditional | Only if the athlete spars hard ≥ 2×/week |
| Hard conditioning after skill training, never before sparring | Mostly accurate, incomplete for lifters | Keep ≥ 6 h (ideally 24 h) between hard conditioning and strength work; lift first on shared days; prefer bike/rower over running; explosive power is the quality most blunted by same-session concurrent training ([Robineau 2016](https://journals.lww.com/nsca-jscr/fulltext/2016/03000/specific_training_effects_of_concurrent_aerobic.10.aspx), [Wilson 2012](https://pubmed.ncbi.nlm.nih.gov/22002517/), [2022 meta-analysis](https://pubmed.ncbi.nlm.nih.gov/35476184/)) |

**Corrected default protocol**

- *Setup:* HRmax = 208 − 0.7 × age or a measured value; optional resting HR enables Karvonen; RPE
  always shown and is the only target for users on HR-affecting medication (beta-blockers).
- *Weeks 1–4, aerobic emphasis:* 2–3 × 30–60 min at 60–75 % HRmax (50–70 % HRR), RPE 3–4, talk test;
  bike, rower, swim or run. Maintenance: 1 × week 4–6 × 8 s bursts at RPE 8, 90 s rest.
- *Weeks 5–8, lactic emphasis:* 1–2 × week, ≥ 48 h apart: 30 s on / 2 min off × 6–8 or 45 s / 3 min
  × 4–6 at RPE 9 ("hard but repeatable"); keep 1–2 aerobic sessions. Beginners start at the low
  round count.
- *Weeks 9–12, alactic emphasis:* 2 × week, 5–8 s maximal, 60–120 s rest, 2–3 sets × 4–5 reps,
  3–5 min between sets — HR is not a useful target, cue maximal intent; stop a set if output drops
  ~10 %. Keep 1 aerobic session; lactic optional only for athletes not sparring hard; taper the final week.
- *Around 3–5 strength sessions a week:* easy aerobic right after lifting or on off days;
  lactic/alactic ≥ 6 h (ideally 24 h) from heavy lower-body lifting and from sparring; hard sparring
  counts as a lactic session; at most 2 truly hard conditioning sessions a week.

**Safety content the app must show** ([ACSM pre-participation](https://pubmed.ncbi.nlm.nih.gov/26473759/)):
medical disclaimer + "consult a physician" for inactive users or those with cardiovascular,
metabolic or renal disease/symptoms (all lactic/alactic work counts as vigorous); HRmax is an
estimate; HR zones invalid on beta-blockers → RPE; stop on chest pain, dizziness or unusual
breathlessness; no all-out sprints for beginners before ~4 weeks of base (offer an 85–90 % option);
thorough warm-up before sprints, prefer bike/rower for maximal efforts; no hard conditioning during
a weight cut or while dehydrated.

**Marketing claims.** Defensible: "structured, evidence-informed conditioning periodized for combat
sports", "guides intensity with your own heart-rate zones", "designed to fit around your lifting",
"consistent training improves aerobic fitness and repeat-sprint ability", and conditional promises
("follow the plan consistently and you should see measurable improvements"). **Never:** guaranteed
outcomes or numbers ("never gas out", "+X % VO₂max"), "flushes lactic acid", "zero effect on your
gains", medical/safe-for-everyone claims, or implied endorsement by named coaches.

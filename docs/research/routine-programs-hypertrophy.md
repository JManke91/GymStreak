# Research: Ready-made hypertrophy programs — Beginner Full Body and Push/Pull/Legs

**Status:** research only, no code changed. Researched 2026-09-27.
**Bar set by the product owner:** every program must be scientifically supported **and** community
accepted. Nothing below is invented: every structural choice traces to a meta-analysis/position
stand [numbered sources] and to an established, community-endorsed program. Where this document
adapts a community program (e.g. converting 5×5 linear progression to rep ranges), the adaptation
and its reason are stated explicitly.

Seed keys are written in short form (`barbell_back_squat`); the full key in
`GymStreak/Data/Seeding/SeedExerciseCatalog.swift` is `seed.exercise.<short key>`.

---

## 1. Summary / recommendation

| | **A — Beginner Full Body** | **B — Push/Pull/Legs** |
|---|---|---|
| Audience | No gym experience, goal: build muscle | ~3+ months of training (graduates of A), goal: build muscle |
| Routines | 2 (Workout A, Workout B), alternated | 3 (Push, Pull, Legs) |
| Schedule | 3×/week, non-consecutive (Mon/Wed/Fri), A-B-A then B-A-B | 6×/week: Push/Pull/Legs/Push/Pull/Legs/Rest |
| Per-muscle frequency | ~3×/week (every session is full body) | 2×/week |
| Weekly direct sets/muscle | ~7–10 | ~10–20 |
| Rep ranges | 8–12 compounds (ACSM novice), 10–15 / 12–20 isolations | 6–10 main compound, 8–12 secondary, 10–20 isolations |
| Rest | 150–180 s main lifts, 120 s other compounds, 60–90 s isolations | same |
| Effort | Stop 1–3 reps short of failure (RIR 1–3); last set may go to ~0–1 RIR on isolations | same |
| Progression | Rep-range double progression (the app's model) | same |
| Deload | Not scheduled; reactive only (optional for v1) | same |
| Lineage | r/Fitness Basic Beginner Routine (A/B, 3×/wk) + ACSM novice guidance | Metallicadpa's r/Fitness PPL (6-day), hypertrophy-adapted |

**3-day PPL is not recommended** as a shipped variant: it drops per-muscle frequency to 1×/week,
which Schoenfeld 2016 found inferior to 2×/week [3], and the PPL's own author discourages it
("You *could*… " — recommends a 3-day full-body program instead) [15]. A user with 3 days
should be pointed to Program A.

---

## 2. Evidence base

### 2.1 Weekly volume
- Graded dose-response: each additional weekly set ≈ +0.37 % muscle growth; 10+ sets/muscle/week
  trended best among <5, 5–9, 10+ categories [1].
- Pelland et al. 2026 (Sports Med, 56:481–505), the largest dose-response meta-regression to date:
  volume increases hypertrophy with **diminishing returns**; they recommend counting indirect sets
  fractionally (e.g. bench press counts ~0.5 for triceps) [2]. Hence both programs are budgeted in
  "fractional" sets.
- Per-session volume: a companion **preprint** (Remmert et al. 2025, SportRxiv, not peer-reviewed)
  estimates diminishing returns beyond ~11 fractional sets per muscle per session [12]. Relevant for
  why PPL-3-day (all weekly volume in one session) is less efficient. *Flag: preprint.*

### 2.2 Frequency
- Volume-equated, 2×/week per muscle beats 1×/week; 3× vs 2× undetermined [3].
- Updated meta-analysis: when volume is equated, frequency does not meaningfully affect hypertrophy;
  non-volume-equated studies favour higher frequency modestly [4].
- Pelland 2026: frequency's effect on hypertrophy is compatible with negligible; on strength it is
  positive [2].
- **Practical reading:** frequency is mainly a vehicle for distributing volume. ≥2×/week per muscle is
  the evidence-backed floor; both programs meet it.
- ACSM: novices 2–3 d/week, intermediate 3–4, advanced 4–5; emphasis on multi-joint, total-body
  exercises [5].

### 2.3 Load / rep range
- Hypertrophy is similar across a wide loading spectrum when sets are taken close to failure;
  heavy loads are better for 1RM strength [6][7].
- ACSM: novices 8–12 RM; intermediate/advanced 1–12 RM with emphasis on 6–12 RM for hypertrophy [5].
- Implication: rep ranges are chosen for practicality — 6–10 on heavy barbell lifts (fewer reps where
  technique degrades with fatigue), 8–15 on machines/cables, 12–20 on small-muscle isolation
  (lateral raises, face pulls, calves), where small absolute load jumps otherwise make progression hard.

### 2.4 Rest intervals
- Bayesian meta-analysis (Singer et al. 2024): small benefit of resting **>60 s**; no appreciable
  difference **beyond 90 s** [8].
- RCT in trained men: 3 min > 1 min for strength and quadriceps hypertrophy on multi-joint lifts [9].
- ACSM: 1–2 min for hypertrophy, 3–5 min for heavy core lifts [5].
- Choice: ≥90 s for everything that is not superset-paired; 150–180 s on heavy barbell compounds
  (performance on following sets, per [9]); 60 s inside supersets that pair non-competing muscles
  (each muscle still rests well over 90 s).

### 2.5 Proximity to failure
- Failure vs non-failure: trivial overall advantage, none for momentary-failure subgroup [10].
- Dose-response meta-regression: hypertrophy improves as sets end closer to failure; strength does not
  depend on RIR [11].
- Choice: **1–3 reps in reserve** on compounds; isolations may go to ~0–1 RIR on the last set.
  Also the practical meaning of "reach the top of the range": a set counts only if done with good form
  and ≥1 RIR on barbell lifts.

### 2.6 Exercise selection and order
- ACSM: multi-joint before single-joint, large before small [5].
- Order does not change hypertrophy; it favours strength in whichever lift is done first [13] — so
  main lifts go first.
- In untrained people, adding single-joint arm work to multi-joint training gave no strength benefit
  but small, significant extra arm circumference gains [16][17]. Hence Program A keeps isolation
  work minimal (1 per session per region) and Program B adds more.

### 2.7 Deloads
- Consensus definition exists (Delphi, coaches) but no evidence-based schedule [18].
- RCT: a 1-week mid-program deload did **not** improve hypertrophy and slightly reduced strength gains
  over 9 weeks [19].
- Conclusion: scheduled deloads are **optional**, not essential for either program. The community
  programs use **reactive** deloads (reduce ~10 % after repeated failure) [14][15].

### 2.8 Beginner specifics
- Novice: 8–12 RM, 2–3 d/week; multiple-set programs for hypertrophy; emphasis on multi-joint
  exercises [5]. Beginners grow from modest volume;
  the dose-response slope still holds but gains are large at any reasonable volume [1][2].
- r/Fitness wiki recommends its Basic Beginner Routine for "a maximum of three months" before
  moving on [14] — this is the natural hand-off point from A to B.

---

## 3. Program A — Beginner Full Body

**Schedule:** 3 sessions/week on non-consecutive days (e.g. Mon/Wed/Fri), alternating A and B:
week 1 A-B-A, week 2 B-A-B. Structure copied from the r/Fitness Basic Beginner Routine [14]
("alternate between Workout A and Workout B, leaving one full day of rest between each day").
Duration: ~12 weeks, then offer Program B [14].

**Why A/B instead of one routine:** each session still trains every major region (squat or hinge,
horizontal push, pull), but alternating exercises spreads joint stress and covers vertical + horizontal
patterns — exactly the A/B design of the r/Fitness routine and GZCLP [14][20].

### Workout A

| # | Exercise | Seed key | Sets | Rep range | Rest s | Notes |
|---|---|---|---|---|---|---|
| 1 | Barbell back squat | `barbell_back_squat` | 3 | 8–12 | 180 | Main lift. `goblet_squat` or `leg_press` if barbell technique is not yet there |
| 2 | Barbell bench press | `barbell_bench_press` | 3 | 8–12 | 150 | Main lift. Sub: `dumbbell_bench_press` / `machine_chest_press` |
| 3 | Lat pulldown | `lat_pulldown` | 3 | 8–12 | 120 | Vertical pull (r/Fitness uses chin-ups; pulldown is scalable to beginners) |
| 4 | Lying leg curl | `lying_leg_curl` | 2 | 10–15 | 90 | Hamstring isolation (squat day has no hinge) |
| 5 | Dumbbell lateral raise | `dumbbell_lateral_raise` | 2 | 12–20 | 60 | Superset pos. 0 |
| 6 | Tricep pushdown | `tricep_pushdown` | 2 | 10–15 | 60 | Superset pos. 1 |

### Workout B

| # | Exercise | Seed key | Sets | Rep range | Rest s | Notes |
|---|---|---|---|---|---|---|
| 1 | Romanian deadlift | `romanian_deadlift` | 3 | 8–12 | 180 | Hinge. Replaces r/Fitness 3×5+ conventional deadlift — see §6 |
| 2 | Overhead press | `overhead_press` | 3 | 8–12 | 150 | Sub: `seated_dumbbell_shoulder_press` / `machine_shoulder_press` |
| 3 | Seated cable row | `seated_cable_row` | 3 | 8–12 | 120 | Horizontal pull (r/Fitness uses barbell row; cable row is lower-skill) |
| 4 | Leg press | `leg_press` | 3 | 10–15 | 120 | Second quad stimulus of the week |
| 5 | Incline dumbbell bench press | `incline_dumbbell_bench_press` | 2 | 8–12 | 120 | Keeps chest at ≥2 exposures/week |
| 6 | Dumbbell curl | `dumbbell_curl` | 2 | 10–15 | 60 | Arm isolation (small but real benefit, [16][17]) |

**Weekly direct sets (average of A-B-A / B-A-B = 1.5 of each workout):** quads ~9, hamstrings/glutes
~7.5, chest ~7.5 (+ fractional from OHP), back ~9, side delts ~3 (+ fractional from pressing), biceps
~3 + ~4.5 fractional from pulls, triceps ~3 + ~6 fractional from presses. This sits at the low-moderate
end of the dose-response [1][2] — appropriate for novices (ACSM: multiple-set programs, 8–12 RM [5];
the exact 1–3-sets figure is in the full text, not verified), and leaves room for Program B to add volume.

**Progression:** double progression — all sets reach the top of the range with good form and ≥1 RIR
→ add the smallest increment (2.5 kg lower-body barbell, 1.25–2.5 kg upper-body barbell, one
pin/plate on machines), reset to the bottom of the range. A reset is expected when reps fall below the
lower bound in two consecutive sessions: reduce load ~10 % (mirrors [14][15]).

**Deload:** none scheduled (see 2.7). Optional for v1.

**Starting weights:** the app starts at 0 kg. Use the Metallicadpa rule adapted to rep ranges: work up
in warm-up sets until a weight is heavy enough that ~the lower bound of the range is ~2–3 RIR; start
there [15].

---

## 4. Program B — Push/Pull/Legs

**Schedule (recommended):** 6 days, Push/Pull/Legs/Push/Pull/Legs/Rest — the layout of
Metallicadpa's PPL ("PPLRPPL" or "PPLPPLR") [15]. Each muscle is trained 2×/week, which meets the
evidence floor [3][4]; weekly volume per muscle lands at ~10–20 sets, the range where Pelland's
dose-response still shows meaningful gains [2]. The same 3 routines run twice per week.

**Adaptation from the source:** Metallicadpa's main lifts are 5-rep linear progression with AMRAP
last sets and weekly alternation of bench/OHP and deadlift/row. For a hypertrophy program on the
app's double-progression model the main lifts are converted to 6–10 rep ranges (within ACSM's
6–12 RM hypertrophy emphasis [5]; hypertrophy equivalent across loads [6][7]), and the alternation
is flattened so there are exactly 3 routines (bench is always the first push lift, row the first pull
lift). Accessories are kept almost unchanged — they already use 8–12 / 15–20 double progression
("progress when you can complete 3 sets of 12") [15].

### Push

| # | Exercise | Seed key | Sets | Rep range | Rest s | Notes |
|---|---|---|---|---|---|---|
| 1 | Barbell bench press | `barbell_bench_press` | 4 | 6–10 | 180 | Main lift (source: 4×5, 1×5+) |
| 2 | Overhead press | `overhead_press` | 3 | 8–12 | 150 | Source: "opposite pressing movement 3×8–12" |
| 3 | Incline dumbbell bench press | `incline_dumbbell_bench_press` | 3 | 8–12 | 120 | As source |
| 4 | Tricep pushdown | `tricep_pushdown` | 3 | 8–12 | 60 | Superset pos. 0 (as source) |
| 5 | Dumbbell lateral raise | `dumbbell_lateral_raise` | 3 | 15–20 | 60 | Superset pos. 1 (as source) |
| 6 | Overhead tricep extension | `overhead_tricep_extension` | 3 | 8–12 | 60 | Superset pos. 0 (as source) |
| 7 | Cable lateral raise | `cable_lateral_raise` | 3 | 15–20 | 60 | Superset pos. 1. Source repeats lateral raises; cable variant avoids a duplicate exercise in one routine |

### Pull

| # | Exercise | Seed key | Sets | Rep range | Rest s | Notes |
|---|---|---|---|---|---|---|
| 1 | Deadlift | `deadlift` | 2 | 4–6 | 180 | Low-volume heavy hinge, first while fresh (source: 1×5+, alternating weekly with row). Added at content sign-off (product owner, 2026-09-27) |
| 2 | Barbell row | `barbell_row` | 3 | 6–10 | 150 | Source: 4×5, 1×5+, alternating with deadlift. One set fewer than the source so the session and lower-back load stay in check with deadlift in front |
| 3 | Lat pulldown | `lat_pulldown` | 3 | 8–12 | 120 | Source: "pulldowns/pull-ups/chin-ups". Sub: `pull_up`, `assisted_pull_up` |
| 4 | Seated cable row | `seated_cable_row` | 3 | 8–12 | 120 | Source: "seated cable rows or chest-supported rows" |
| 5 | Face pull | `face_pull` | 5 | 15–20 | 60 | As source |
| 6 | Hammer curl | `hammer_curl` | 4 | 8–12 | 60 | As source |
| 7 | Dumbbell curl | `dumbbell_curl` | 4 | 8–12 | 60 | As source |

### Legs

| # | Exercise | Seed key | Sets | Rep range | Rest s | Notes |
|---|---|---|---|---|---|---|
| 1 | Barbell back squat | `barbell_back_squat` | 3 | 6–10 | 180 | Main lift (source: 2×5, 1×5+) |
| 2 | Romanian deadlift | `romanian_deadlift` | 3 | 8–12 | 150 | As source |
| 3 | Leg press | `leg_press` | 3 | 8–12 | 120 | As source |
| 4 | Lying leg curl | `lying_leg_curl` | 3 | 8–12 | 90 | As source ("leg curls"); `seated_leg_curl` equally valid |
| 5 | Standing calf raise | `standing_calf_raise` | 5 | 8–12 | 60 | As source |
| 6 | Cable crunch (optional) | `cable_crunch` | 3 | 10–15 | 60 | Source: "ab work on squat/deadlift days" (weighted planks, ab wheel, hanging leg raises). Cable crunch chosen because it is loadable and so fits double progression |

**Weekly direct sets (×2 sessions):** chest 14, back 18 (+ face pulls, + 4 deadlift sets that load
back, glutes and hamstrings), quads 12, hamstrings 12 (+ deadlift),
side delts 12, rear delts 10, biceps 16 + fractional from pulls, triceps 12 + fractional from presses,
calves 10. Upper-body pull volume is high but is the source program's own prescription [15].

**Progression:** identical double progression to Program A. **Deload:** reactive only (source: fail a
lift 3 sessions in a row → −10 % [15]); no scheduled deload (2.7).

---

## 5. Fit with the app's rep-range progression

The app implements **double progression** (`docs/rep-range-progressive-overload.md`): an exercise has
a rep range; when **all sets** reach the upper bound, the app suggests a weight increase (presets
0.5/1.25/2.5/5 kg or 1.25/2.5/5/10 lb), and on apply resets every set's reps to the lower bound.

**Where it fits**
- All accessory work in both source programs already uses exactly this model (Metallicadpa: "3 sets
  of 12 → add weight" [15]; GZCLP T3: add weight at 25+ reps [20]).
- The rep ranges above are wide enough (4–5 reps; 5 on isolations) that a small increment lands
  back inside the range after reset.
- ACSM's progression guidance is exactly this: increase load 2–10 % once the current load can be
  performed for 1–2 reps above the target [5].

**Where it does not fit (and what is lost)**
| Community mechanism | Source | App support | Impact / recommendation |
|---|---|---|---|
| Linear progression: add weight **every session** on main lifts | [14][15][20] | No — weight only rises after the top of the range | Beginners progress somewhat slower on main lifts in weeks 1–6. Acceptable for a hypertrophy goal (hypertrophy is load-independent across ranges [6][7]); this is the deliberate adaptation of §4 |
| AMRAP last set (`5+`) | [14][15][20] | No set type for it | Replaced by rep ranges; not needed |
| Reactive deload after repeated failure (−10 %) | [14][15] | No failure counter or decrease suggestion | Document it in the program description; optional future feature |
| Stage changes (GZCLP 5×3 → 6×2 → 10×1) | [20] | No | Not used in these programs |
| Weekly alternation of main lifts (bench/OHP, deadlift/row) | [15] | Would need 5–6 routines | Flattened to 3 routines (§4) |
| A/B alternation on Mon/Wed/Fri | [14] | `RoutineSchedule` is per routine (weekday mask or every-N-days); "A-B-A then B-A-B" cannot be expressed | Needs a "next routine in program" concept, or approximate: A = Mon/Fri, B = Wed (unequal exposure) |
| RIR / effort target | [10][11] | No field | Put "stop 1–3 reps short of failure" in program text |
| Timed holds (planks) | — | Logged as 1 rep/set | Avoided: `cable_crunch` used instead |
| Different increments upper vs lower body | [14][15] | User picks increment each time | Program text: default 2.5 kg lower / 1.25–2.5 kg upper |

---

## 6. Community acceptance / lineage

- **r/Fitness wiki** lists as beginner routines: r/Fitness Basic Beginner Routine; as barbell routines
  also GZCLP, Metallicadpa's PPL, nSuns LP, 5/3/1, Greg Nuckols' SBS bundle, PHAT [21]. It states
  "all of the programs on this page are effective at getting you both bigger and stronger" [21].
- **Program A** ← r/Fitness Basic Beginner Routine (A/B, 3×/week, squat/bench/row vs
  deadlift/OHP/chin-up) [14]; exercise count and rep ranges ← ACSM novice guidance [5]. Deviations:
  3×5+ LP → 3×8–12 double progression; conventional deadlift → RDL (lower technical demand, suits
  8–12 reps; hypertrophy of glutes/hamstrings covered); barbell row → cable row; small isolation block
  added (GZCLP likewise adds a T3 lat pulldown / dumbbell row [20]).
- **Program B** ← Metallicadpa, "A Linear Progression Based PPL Program for Beginners", r/Fitness 2015
  [15], listed on the r/Fitness wiki [21]. Accessories kept as written; main lifts converted to rep
  ranges; deadlift kept as a low-volume first Pull lift (2×4–6) instead of the weekly alternation.
- **Stronger by Science** (Nuckols): recommends periodizing novice programs (e.g. 3×8 → 5×5 → 5×3)
  and adding sets instead of repeating a −10 % reset when progress stalls [22]; its commercial
  "SBS Novice Hypertrophy" template exists but its content is paywalled and **was not verified** [23].
- **Contrast — StrongLifts 5×5 / Starting Strength:** strength-first 5-rep linear progression with
  almost no isolation work. Not used, because the goal here is muscle, and the r/Fitness wiki itself
  replaced them with the Basic Beginner Routine. *Not verified from their primary pages (not fetched);
  characterisation from the Metallicadpa post, which names them as the 3-day alternatives [15].*
- **Jeff Nippard / Renaissance Periodization:** commercial programs; not used as sources and not
  verified. The designs above are consistent with their public principles (2×/week frequency,
  10–20 sets, 1–3 RIR, rep ranges), but no claim of derivation is made.

---

## 7. Missing catalog exercises

Every exercise in both programs maps to an existing seed key. Only optional source-program
alternatives are missing:

| Exercise | Used by | Catalog substitute used | Priority |
|---|---|---|---|
| Chest-supported row (dumbbell/machine) | Metallicadpa alt. to cable row [15] | `seated_cable_row` (or `machine_row`) | Low |
| Cable overhead triceps extension | Common variant of overhead extension | `overhead_tricep_extension` (dumbbell) | Low |
| Weighted plank | Metallicadpa ab option [15] | `cable_crunch` | Low (timed sets unsupported anyway) |

---

## 8. Open questions for the product owner

> **Resolved at content sign-off (2026-09-27, wayfinder ticket 06).** (1) No rotation concept;
> every-N-days cadence per routine — Full Body A/B each every 4 days offset 2 (exact alternation,
> one rest day between sessions), PPL each every 3 days offset 0/1/2 with a program-text rest-day
> rule. (2) Deadlift **back in** as Pull #1, 2×4–6, row reduced to 3 sets (§4). (3) 6-day PPL only;
> 3-day users → Program A; an Upper/Lower program is planned follow-up work. (4) Barbell defaults with
> machine alternatives attached. (5) Effort, reactive deload, increments, start weights and
> graduation are program text only in v1; stall detection is a follow-up feature. (6) No abs in
> Program A. The questions are kept below as the record of what was asked.

1. **Program / rotation concept.** Program A needs "next routine = the other one", Program B needs a
   fixed 3-routine order. Ship as independent routines with weekday schedules (PPL works: Push Mon/Thu,
   Pull Tue/Fri, Legs Wed/Sat; A/B cannot be expressed exactly), or build a program sequence?
2. **Deadlift in PPL.** Drop conventional deadlift (current proposal, RDL covers the hinge) or add it
   as a low-volume first lift on Pull (source: 1×5+ every other week)?
3. **3-day PPL variant.** Recommend not shipping it (evidence + source author); OK?
4. **Barbell vs machine defaults for beginners.** Program A uses barbell main lifts (community
   standard). A more beginner-friendly default would be `leg_press`/`machine_chest_press`/
   `machine_shoulder_press`. Which default?
5. **Effort guidance / reactive deload.** Put "1–3 RIR" and "−10 % after 2–3 stalled sessions" in the
   program description text only, or is an app feature wanted later?
6. **Abs in Program A.** Omitted (no evidence need; keeps sessions short). Add `cable_crunch` 2×10–15?

---

## 9. Sources

1. Schoenfeld BJ, Ogborn D, Krieger JW. Dose-response relationship between weekly resistance training
   volume and increases in muscle mass. *J Sports Sci* 2017;35:1073–1082. doi:10.1080/02640414.2016.1210197 (PMID 27433992)
2. Pelland JC, Remmert JF, Robinson ZP, Hinson SR, Zourdos MC. The resistance training dose response:
   meta-regressions exploring the effects of weekly volume and frequency on muscle hypertrophy and
   strength gains. *Sports Med* 2026;56:481–505. doi:10.1007/s40279-025-02344-w (PMID 41343037)
   (preprint 2024: https://sportrxiv.org/index.php/server/preprint/view/460)
3. Schoenfeld BJ, Ogborn D, Krieger JW. Effects of resistance training frequency on measures of muscle
   hypertrophy. *Sports Med* 2016;46:1689–1697. doi:10.1007/s40279-016-0543-8 (PMID 27102172)
4. Schoenfeld BJ, Grgic J, Krieger J. How many times per week should a muscle be trained to maximize
   muscle hypertrophy? *J Sports Sci* 2019;37:1286–1295. doi:10.1080/02640414.2018.1555906 (PMID 30558493)
5. American College of Sports Medicine. Position stand: Progression models in resistance training for
   healthy adults. *Med Sci Sports Exerc* 2009;41:687–708. doi:10.1249/MSS.0b013e3181915670 (PMID 19204579)
6. Schoenfeld BJ, Grgic J, Ogborn D, Krieger JW. Strength and hypertrophy adaptations between low- vs.
   high-load resistance training. *J Strength Cond Res* 2017;31:3508–3523. doi:10.1519/JSC.0000000000002200
7. Schoenfeld BJ, Grgic J, Van Every DW, Plotkin DL. Loading recommendations for muscle strength,
   hypertrophy, and local endurance: a re-examination of the repetition continuum. *Sports* 2021;9:32.
   doi:10.3390/sports9020032
8. Singer A, Wolf M, Generoso L, et al. Give it a rest: a systematic review with Bayesian meta-analysis on
   the effect of inter-set rest interval duration on muscle hypertrophy. *Front Sports Act Living*
   2024;6:1429789. doi:10.3389/fspor.2024.1429789
9. Schoenfeld BJ, Pope ZK, Benik FM, et al. Longer interset rest periods enhance muscle strength and
   hypertrophy in resistance-trained men. *J Strength Cond Res* 2016;30:1805–1812. doi:10.1519/JSC.0000000000001272
10. Refalo MC, Helms ER, Trexler ET, Hamilton DL, Fyfe JJ. Influence of resistance training
    proximity-to-failure on skeletal muscle hypertrophy. *Sports Med* 2023;53:649–665. doi:10.1007/s40279-022-01784-y
11. Robinson ZP, Pelland JC, Remmert JF, et al. Exploring the dose-response relationship between estimated
    resistance training proximity to failure, strength gain, and muscle hypertrophy. *Sports Med*
    2024;54:2209–2231. doi:10.1007/s40279-024-02069-2
12. Remmert JF, Pelland JC, Robinson ZP, Hinson SR, Zourdos MC. Is there too much of a good thing?
    Meta-regressions of the effect of per-session volume on hypertrophy and strength. SportRxiv
    preprint, 2025 (not peer-reviewed). https://sportrxiv.org/index.php/server/preprint/view/537
13. Nunes JP, Grgic J, Cunha PM, et al. What influence does resistance exercise order have on muscular
    strength gains and muscle hypertrophy? *Eur J Sport Sci* 2021;21:149–157. doi:10.1080/17461391.2020.1733672
14. r/Fitness wiki — Basic Beginner Routine. https://thefitness.wiki/routines/r-fitness-basic-beginner-routine/
15. u/Metallicadpa. A Linear Progression Based PPL Program for Beginners. r/Fitness, 2015.
    https://old.reddit.com/r/Fitness/comments/37ylk5/a_linear_progression_based_ppl_program_for/ —
    read via the r/Fitness wiki archive copy (reddit blocked fetching):
    https://thefitness.wiki/reddit-archive/a-linear-progression-based-ppl-program-for-beginners/
16. Barbalho M, Gentil P, Raiol R, et al. Influence of adding single-joint exercise to a multijoint
    resistance training program in untrained young women. *J Strength Cond Res* 2020;34:2214–2219.
    doi:10.1519/JSC.0000000000002624
17. Barbalho M, Coswig VS, Raiol R, et al. Does the addition of single joint exercises to a resistance
    training program improve changes in performance and anthropometric measures in untrained men?
    *Eur J Transl Myol* 2018;28:7827. doi:10.4081/ejtm.2018.7827
18. Bell L, Strafford BW, Coleman M, Androulakis Korakakis P, Nolan D. Integrating deloading into strength
    and physique sports training programmes: an international Delphi consensus approach.
    *Sports Med Open* 2023;9:87. doi:10.1186/s40798-023-00633-0
19. Coleman M, Burke R, Augustin F, et al. Gaining more from doing less? The effects of a one-week deload
    period during supervised resistance training on muscular adaptations. *PeerJ* 2024;12:e16777.
    doi:10.7717/peerj.16777
20. r/Fitness wiki — GZCLP (Cody LeFever, u/gzcl). https://thefitness.wiki/routines/gzclp/ ;
    original: https://old.reddit.com/r/Fitness/comments/44hnbc/strength_training_using_the_gzcl_method_from/
    (original not fetched — reddit blocked)
21. r/Fitness wiki — Strength training / muscle building routines.
    https://thefitness.wiki/routines/strength-training-muscle-building/
22. Nuckols G. Two easy ways to make your novice strength training program more effective. Stronger by
    Science. https://www.strongerbyscience.com/making-your-novice-strength-training-routine-more-effective-two-quick-tips/
23. Stronger by Science Program Bundle (SBS Novice Hypertrophy — contents paywalled, not verified).
    https://www.strongerbyscience.com/program-bundle/

**Verification notes.** Journal abstracts were read via Europe PMC (PubMed served a captcha). Reddit
originals could not be fetched; program details come from the r/Fitness wiki's own pages and archive.
Commercial programs (SBS, Nippard, RP, StrongLifts, Starting Strength) were not verified at source.

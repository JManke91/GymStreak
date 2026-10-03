# Research: Ready-made strength program — Fighter Strength

**Status:** research only, no code changed. Researched 2026-09-27 (wayfinder ticket
`.scratch/_done/routine-programs/wayfinder/02-research-fighter-strength.md`).
**Bar set by the product owner:** every program must be scientifically supported **and** community
accepted. Nothing below is invented: the structure traces to peer-reviewed combat-sport S&C
literature, meta-analyses and NSCA guidance [numbered sources], and to the one published,
peer-reviewed training intervention in professional MMA fighters that reports its full prescription
(Kostikiadis et al. 2018 [1]). Where this document adapts a source, the adaptation and its reason are
stated explicitly.
**Scope (map decision 2026-09-27):** Fighter Strength is **lifting only**. Conditioning stays in the
existing fight-conditioning add-on (`docs/fight-conditioning.md`); skill training is out of scope. This
document only explains how the lifting week coexists with both.

Seed keys are written in short form (`barbell_back_squat`); the full key in
`GymStreak/Data/Seeding/SeedExerciseCatalog.swift` is `seed.exercise.<short key>`. Every key used
below was checked against that file on 2026-09-27.

---

## 1. Summary / recommendation

| | **Fighter Strength** |
|---|---|
| Audience | Combat athletes (MMA, boxing, kickboxing/Muay Thai, BJJ/wrestling) who train their sport 3+ times a week and want to be stronger and more explosive without adding much bulk |
| Routines | 2 full-body sessions: **A — Squat & Press**, **B — Hinge & Pull** |
| Schedule | 2×/week, ≥ 48 h apart (default Mon/Thu); never on or the day before a hard sparring day |
| Session order | Power exercise first (fresh) → heavy strength lift → upper-body strength pair → unilateral/trunk |
| Strength lifts | 3–4 sets × 3–5 reps (~80–88 % 1RM), 1–3 reps in reserve, **180 s** rest |
| Power lifts | 3–4 sets × 3 reps, light-to-moderate load, maximal intent, 120–180 s rest, no rep-range goal |
| Accessories | 2–3 sets × 6–10 reps, 90–120 s rest |
| Progression | Rep-range double progression on strength lifts and accessories (fits the app); power lifts progress by feel/technique (program text) |
| Periodization | Strength-emphasis → power-emphasis blocks aligned with the conditioning program's 12 weeks; final 2 weeks volume −40–60 % at maintained load |
| Lineage | Kostikiadis 2018 MMA intervention [1]; Ruddock 2016 boxing recommendations [2]; NSCA load/rep and seasonal-frequency guidance [3]; Suchomel strength and weightlifting-derivative reviews [4][5][6] |
| Blocking gap | **The catalog has no ballistic exercise at all** (no jump, throw, clean or pull derivative). The power half of the program needs **5 new seeds** (§8, incl. the hang power clean alternative). Without them the program is a plain low-rep strength program, not "Fighter Strength" |

**Why 2 sessions, not 3:** fighters already carry 3–12 sport sessions a week [7], and NSCA guidance
cuts resistance-training frequency to 1–3 sessions in-season and 3–4 pre-season [3]; strength is
maintained on as little as one session a week if load is kept high [8][9]. Two sessions is the
frequency that still *improves* strength and power while leaving room for sparring and the
conditioning program's two hard sessions. A 3-day off-season variant is an open question (§9).

---

## 2. Evidence base

### 2.1 Why strength and power matter for fighters
- Greater maximal strength improves force–time characteristics, jumping, sprinting and change of
  direction, enhances potentiation and lowers injury risk; "there may be no substitute for greater
  muscular strength" [4].
- Punch impact in elite amateur boxers correlated **r = 0.67–0.85** with jump height, jump-squat power,
  bench press and bench throw, and rate of force development [10].
- Systematic review of combat sports (MMA-oriented): grappling success tracks higher *maximal* strength
  (upward shift of the force–velocity curve); striking success tracks lighter-load, higher-velocity
  output; anaerobic capacity separates higher- from lower-level athletes [11].
- Boxing reviews and position articles recommend key lifts with forceful hip extension (squats,
  deadlifts, Olympic lifts) **plus** low-external-load jump training for rate of force development [2];
  Muay Thai [12] and MMA [13][14] S&C reviews make the same strength + power case (full texts of
  [12][13][14] are paywalled — only abstracts/metadata verified).
- Practice gap: in a 2025 survey of 72 boxing practitioners, 84 % agreed maximal-strength training
  improves punching power, yet it was the *least* programmed quality, partly from fear of unwanted
  muscle mass [15]. An MMA survey found only 8 of 28 fighters used power cleans/snatches [7]. A ready
  program that is explicitly low-volume and strength-first addresses exactly this gap.

### 2.2 Strength first, then power (sequencing)
- Weaker athletes should prioritise strength; block periodization (strength → power) likely gives the
  greatest strength–power benefit, but must fit the sport's schedule [5].
- In relatively weak men, 10 weeks of heavy squats (75–90 % 1RM) improved jump and sprint as much as
  ballistic jump-squat training, with longer-term benefit from the strength gained — so strength
  training is "a more effective training modality for relatively weak individuals" [16]. In a paired
  study the strength level did **not** significantly change the size of gains from ballistic training
  (only a tendency favouring stronger men) [17].
- Practical reading: both qualities are trained every week (mixed-methods, [18]), but the *emphasis*
  shifts from strength to power across a camp. The program never removes the heavy lift.

### 2.3 Power exercise selection
- Weightlifting (Olympic) training improved vertical jump by 5.1 % more than traditional resistance
  training and matched plyometrics [19]; a second meta-analysis agrees (WL > traditional, WL ≈
  plyometrics for CMJ) [20].
- Weightlifting **pulling derivatives** (jump shrug, hang high pull, clean pull, mid-thigh pull) drop
  the catch, are technically simpler, and keep the triple-extension stimulus — recommended for
  non-weightlifters [6]. This matters for an app with no coach watching: the default power lift is a
  pull derivative, with the hang power clean as the alternative for athletes who already know it.
- Plyometrics: combining jump types (squat jump, CMJ, drop jump) beats one form; added weight gave no
  extra benefit; > 10 weeks and > 20 sessions maximise gains [21].
- Loaded jump squats at 0–30 % 1RM are the standard ballistic-lift dose [16][17]; Kostikiadis used
  30 % in pro MMA fighters [1].
- Horizontal/rotational force transfer: Jamieson (8WeeksOut) prefers explosive throws, bounding and
  horizontal ballistic work because Olympic lifts produce force vertically [22] (practitioner
  interview — community evidence, not peer-reviewed). Medicine-ball chest and "jab" throws are the
  upper-body ballistic exercises in the only published pro-MMA intervention [1].

### 2.4 Load, sets, reps, rest
- NSCA (Essentials, via study guide — **secondary source, book not read directly**): strength ≥ 85 %
  1RM, ≤ 6 reps, 2–6 sets; power multiple-effort 75–85 %, 3–5 reps, 3–5 sets; strength and power rest
  **2–5 min**; power exercises first in the session [3].
- Suchomel 2018: 2–5 min rest gives the greatest strength–power benefit; training to failure is not
  necessary for maximal strength; combining heavy and light loads helps [5].
- Proximity to failure does not drive strength gains (meta-regression) [23] → 1–3 reps in reserve;
  fighters should never grind reps before skill sessions.
- Pro-MMA intervention [1]: 3 sessions/week for 4 weeks, squat/bench/deadlift progressed
  3×8 @ 80 % → 4×5 @ 85 % → 5×3 @ 90 % → 3×2 @ 95 %, 3 min between sets, each set followed by 3
  ballistic reps (CMJ, 2 kg med-ball chest throw, jump shrug @ 45 % deadlift 1RM); a separate power
  day with jump squats 4×8 @ 30 %, drop jumps, 4 kg med-ball jab throws and plyometric push-ups.
  The specific group improved squat/bench/deadlift 1RM, jump power, med-ball throw velocity and 10 m
  sprint; the "regular" circuit-style group improved nothing. *Caveat: n = 17, 4 weeks, not randomised
  (groups matched by squat 1RM) — a strong signal, not proof.*

### 2.5 Concurrent training — the interference that shapes the week
- Strength + endurance: power gains are the most blunted quality (effect sizes 0.91 strength-only vs
  0.55 concurrent); interference grows with endurance frequency and duration and with running more
  than cycling [24].
- Updated meta-analysis (43 studies): concurrent training does **not** compromise maximal strength or
  hypertrophy, but **explosive strength is attenuated (SMD −0.28), more so when both are done in the
  same session**; separating by ≥ 3 h removed the significant effect [25].
- HIIT + resistance: no effect on hypertrophy or upper-body strength, small reduction in lower-body
  strength [26].
- Recovery gap RCT: strength gains were lower with 0 h between strength and aerobic sessions than
  with 6 h or 24 h; coaches should keep ≥ 6 h between contradictory qualities [27].
- These are exactly the rules the fight-conditioning program already enforces (§4).

### 2.6 Frequency and maintenance
- NSCA seasonal frequency: off-season 4–6, pre-season 3–4, in-season 1–3, post-season 0–3 sessions a
  week (secondary source) [3]. These are *total-athlete* figures; a fighter's "season" is the camp.
- One strength session a week maintained pre-season gains in strength and sprint for 12 weeks in
  professional soccer players; one every second week did not [8]. Strength and size are maintained for
  up to 32 weeks with 1 session/week and 1 set/exercise if relative load is kept [9].
- Two sessions a week is therefore enough to improve during a camp and comfortably above maintenance.

### 2.7 Periodization and taper
- Periodized plans beat non-periodized ones for 1RM (ES 0.43 [28]; volume-equated ES 0.31 [29]);
  undulating vs linear differences are small and favour undulating in trained lifters [29].
- Taper meta-analysis: a ~2-week taper with volume reduced 41–60 % and intensity kept is most
  effective [30]; boxing recommendations adopt exactly this for the final 2 weeks before a fight [2].
  Peaking evidence specific to strength athletes is thin [31] — the taper here is an evidence-informed
  convention, not a tested fighter protocol.
- Scheduled deloads: no evidence-based schedule exists (Delphi consensus defines them, [32]); the
  sibling doc found a mid-block deload did not help hypertrophy. For fighters the camp taper *is* the
  scheduled deload.

---

## 3. The program

**Frequency:** 2 sessions/week, full body, ≥ 48 h apart (Kostikiadis spaced sessions 48 h [1]).
Default weekdays **Mon + Thu**; any pair works if the §4 rules hold.
**Warm-up (program text, not logged):** 10 min easy + dynamic mobility, then 2–3 ramp-up sets of the
first strength lift (as in [1]).
**Effort:** strength lifts 1–3 reps in reserve; power lifts stop as soon as a rep looks or feels
slower — "every rep fast" (program text; the app cannot measure velocity).

### Routine A — Squat & Press

| # | Exercise | Seed key | Sets | Reps | Rest s | Notes |
|---|---|---|---|---|---|---|
| 1 | Box jump | **MISSING** `box_jump` | 3 | 3 | 90 | Bodyweight, step down. No rep-range goal. Plyometric, CMJ-type [1][21] |
| 2 | Barbell back squat | `barbell_back_squat` | 4 | 3–5 | 180 | Main strength lift, ~80–88 % 1RM. Alt: `front_squat` |
| 3 | Barbell bench press | `barbell_bench_press` | 4 | 3–5 | 180 | Superset pos. 0 with #4 (contrast pair, as [1]). Alt: `dumbbell_bench_press` |
| 4 | Medicine-ball chest pass | **MISSING** `medicine_ball_chest_pass` | 4 | 3 | 180 | Superset pos. 1: 3 explosive throws right after each bench set (2–4 kg) [1] |
| 5 | Weighted pull-up | `pull_up` | 3 | 4–6 | 150 | Add load via belt once 3×6 bodyweight is easy. Alt: `lat_pulldown` |
| 6 | Bulgarian split squat | `bulgarian_split_squat` | 2 | 6–8 /leg | 120 | Unilateral strength/stance stability [5] |
| 7 | Ab wheel rollout | `ab_wheel_rollout` | 3 | 6–10 | 90 | Trunk bracing ("effective mass", [2]). Pallof press preferred but missing |

### Routine B — Hinge & Pull

| # | Exercise | Seed key | Sets | Reps | Rest s | Notes |
|---|---|---|---|---|---|---|
| 1 | Jump shrug | **MISSING** `jump_shrug` | 4 | 3 | 150 | Pulling derivative, ~30–45 % deadlift 1RM [1][6]. Alt: **MISSING** `hang_power_clean` (for athletes who can catch) |
| 2 | Deadlift | `deadlift` | 3 | 3–5 | 180 | Main strength lift — the lift used in [1]. Trap-bar deadlift was the first draft; dropped at sign-off (substitute is source-backed, no new seed or equipment) |
| 3 | Overhead press | `overhead_press` | 3 | 4–6 | 150 | Alt: `seated_dumbbell_shoulder_press` (landmine press not seeded, see §8) |
| 4 | Pendlay row | `pendlay_row` | 3 | 5–6 | 150 | Explosive from the floor each rep. Alt: `barbell_row` |
| 5 | Rotational med-ball throw | **MISSING** `medicine_ball_rotational_throw` | 3 | 3 /side | 90 | Transverse-plane power, horizontal force [2][22]. No catalog sub |
| 6 | Hanging leg raise | `hanging_leg_raise` | 3 | 8–12 | 90 | Trunk; alt `cable_crunch` |

Neck flexion/extension was drafted as an optional #7 and **dropped at sign-off**: evidence for an
injury/concussion benefit is weak, which fails the program's evidence bar.

**Weekly volume:** ~7–8 hard sets per major lower-body pattern and ~7 per upper push/pull, plus
~13–14 ballistic sets. This is low by hypertrophy standards on purpose: fighters compete in weight
classes, and the sibling doc's dose-response data put meaningful growth at ~10+ sets/muscle/week — the
program stays below that. It will not *guarantee* no weight gain (diet decides that); do not claim it.

**Adaptations from the sources, stated:**
- Kostikiadis [1] ran 3 sessions/week with 3 main lifts per session; this is compressed to 2 sessions
  with one main lower lift each, because the app user also runs the fight-conditioning program and
  hard sparring (the study group did no separate conditioning days beyond in-session HIIT).
- The in-session rowing HIIT and sled sprints of [1] are **dropped** (conditioning belongs to the
  add-on, map decision).
- Drop jumps and plyometric push-ups of [1] are replaced by box jumps (lower landing stress — a
  safety adaptation for unsupervised users) and med-ball throws.
- Jump shrug instead of hang power clean as default, per the non-weightlifter rationale of [6].
- Weekly % 1RM waves (80 → 95 %) become a fixed 3–5 rep range with double progression (the app
  cannot prescribe % 1RM or per-week schemes, §6).

---

## 4. Interlock with fight-conditioning and sparring

The conditioning program (`docs/fight-conditioning.md`) already encodes the concurrent-training
evidence: ≤ 2 hard (lactic/alactic) sessions a week; lactic sessions ≥ 48 h apart; hard work ≥ 6 h
(ideally 24 h) after heavy lower-body lifting; easy aerobic work is fine right after lifting; hard
sparring counts as a lactic session; never hard conditioning on or the day before hard sparring.
Fighter Strength should obey the same rules from the lifting side:

1. **Lift first on shared days**, hard work ≥ 6 h later [25][27]; easy aerobic may follow directly.
2. **No lifting on a hard sparring day or the day before one** (power and skill quality both suffer
   from residual fatigue; same rule the add-on already applies to hard conditioning).
3. **≥ 48 h between the two lifting sessions** [1].
4. **Stack hard on hard, keep easy days easy:** the two lifting days take the add-on's easy aerobic
   sessions; hard conditioning sits on its own day or ≥ 6 h after a lift.

**Example week (sparring Tue + Sat):**

| Day | Lifting | Conditioning add-on | Skill (user's gym) |
|---|---|---|---|
| Mon | **Strength A** (AM) | Easy aerobic right after, or phase-3 alactic ≥ 6 h later | Technique PM |
| Tue | — | — (sparring counts as lactic) | **Hard sparring** |
| Wed | — | Hard session #1 (lactic in wks 5–8 / alactic in 9–11) | Technique |
| Thu | **Strength B** (AM) | Easy aerobic right after | Technique PM |
| Fri | — | Easy aerobic only (day before sparring) | Light drilling |
| Sat | — | — | **Hard sparring** |
| Sun | Rest | Rest | Rest |

**Coach integration finding.** `ConditioningProgramCoach` treats a day as *heavy lower body* when ≥ 2
logged exercises list Quadriceps or Hamstrings. Routine A qualifies (squat + split squat, + box jump if
seeded with Quadriceps). Routine B qualifies only through `deadlift`/`trap_bar_deadlift` **plus** a
second leg-muscle exercise — the new `jump_shrug` / `hang_power_clean` seeds should list Hamstrings
and Quadriceps (they are triple-extension lifts) so the coach steers hard conditioning ≥ 6 h away from
Routine B too. **Decided (ticket 07, 2026-10-03):** both list Hamstrings + Quadriceps; Routine B is heavy lower body (see `docs/starter-exercise-library.md`, "Catalog v3").

**Aligning the two 12-week arcs** (proposed; phase potentiation [5][18], taper [2][30]):

| Conditioning weeks | Conditioning emphasis | Fighter Strength emphasis |
|---|---|---|
| 1–4 | Aerobic base | **Strength**: top of the program — 4 sets on main lifts, full accessories |
| 5–8 | Lactic (hardest block) | **Strength maintenance**: main lifts 3 sets, drop set #6 (unilateral) to keep total fatigue down during the most taxing conditioning |
| 9–11 | Alactic / power | **Power emphasis**: all ballistic sets kept, main lifts 3 × 3 at the same load (lower reps, same intensity [9]) |
| 12 (taper) | Taper | Volume −40–60 %, load kept: main lifts 2 × 3, 2 ballistic sets; last heavy session ≥ 5 days before the fight (practitioner convention, **no fighter-specific evidence**) |

Fight week, weight cut and the day before weigh-ins: no heavy lifting (convention; the add-on already
forbids hard conditioning during a cut). Off-season (no fight booked): run the week-1–4 emphasis
indefinitely.

---

## 5. Progression and fit with the app's rep-range model

The app implements double progression (`docs/rep-range-progressive-overload.md`): all sets reach the
rep-range maximum → suggest +increment (0.5/1.25/2.5/5 kg) → reset reps to the minimum.

**Where it fits**
- **Strength lifts (3–5):** all sets at 5 reps with ≥ 1 RIR → +2.5 kg lower body / +1.25–2.5 kg upper
  → back to 3 reps. At 3–5 reps a 2.5 kg step is ~2 % of a 120 kg squat, inside the NSCA's own
  progression rule ("2-for-2": two extra reps on the final set in two consecutive sessions → add load
  [3]). A two-rep window is narrow but workable; 3–6 was the fallback for more room; content sign-off kept 3–5.
- **Accessories (4–6, 5–6, 6–8, 6–10, 8–12):** identical to the sibling programs.
- **Weighted pull-up:** a bodyweight exercise with `weight` used as added load works with the model;
  `assisted_pull_up` already handles the counterweight direction.

**Where it does not fit**
- **Power lifts (jump shrug, hang power clean, loaded jump squat):** adding reps is the wrong
  progression — reps stay at 3 and load rises only while speed holds. Ship these with **no rep-range
  goal** (`targetRepMin/Max = nil`), so the app never fires a weight-increase suggestion; progression
  lives in program text ("add 2.5–5 kg when every rep is crisp; drop it if reps slow").
- **Jumps and throws (box jump, med-ball throws):** progress by height/distance/speed, not load or
  reps. Log as 3 reps × bodyweight (0 kg) or ball mass; no rep-range goal.
- **Per-phase changes** (§4 table): the app cannot switch sets/reps by program week. Options for the
  delivery-model ticket: (a) ship one fixed version (the weeks 1–4 routine) with the phase guidance as
  text; (b) ship phase variants of each routine; (c) a program layer that swaps set counts by week.
  Recommendation: (a) for v1 — it is the evidence-backed core; the taper is text.

---

## 6. What the app cannot represent

Grounded in the model: `ExerciseSet` holds only `reps`, `weight`, `restTime`, `order`;
`RoutineExercise` adds `targetRepMin/Max`, superset grouping and alternatives; `EquipmentType` is
dumbbell/barbell/machine/cable/bodyweight; schedules are per-routine weekdays or every-N-days.

| Source mechanism | Source | App support | Handling |
|---|---|---|---|
| % 1RM loading (80–95 %) | [1][3] | No prescription field (the app computes Epley e1RM for PRs/progress only) | Rep range + RIR text; future: derive start weights from e1RM |
| Weekly wave / block loading (3×8 → 5×3 → 3×2) | [1][5] | No per-week scheme | Fixed rep range; phase guidance as text (§5) |
| Velocity targets, "stop when speed drops ~10 %" | [5][18] | No velocity or bar-speed capture | Program text: "every rep fast" |
| Jump height / throw distance progression | [21] | Reps + weight only | Log reps; progress by feel |
| Contrast/complex pairing (heavy set → 3 ballistic reps) | [1] | **Representable** via superset (pos. 0 / pos. 1) with rest on the ballistic set | Used in Routine A (#3/#4) |
| Rest *between reps* (12 s intra-rep) | [1] | No | Dropped |
| Time-based sets (Pallof/iso holds, neck isometrics, planks) | [2] | No duration field; logged as reps | Avoided: loadable/rep-based trunk work chosen |
| Per-side reps (split squat, rotational throw) | — | No side field | Rep count means "per side" in the note |
| Medicine ball / kettlebell / trap bar / landmine equipment | [1][2][6] | No `EquipmentType` cases | Seed as `.barbell`/`.bodyweight`, or add an equipment case (seeding ticket) |
| Sparring days as constraints | — | App does not know sparring days (the add-on only has an "I spar hard" flag) | Schedule text; user picks weekdays |
| Pre-fight taper tied to a fight date | [2][30] | No event date | Text; possible later feature |
| RIR / effort target | [23] | No field | Program text |

---

## 7. Community acceptance / lineage

- **Kostikiadis et al. 2018** [1] — peer-reviewed intervention in national-level professional MMA
  fighters (heavy squat/bench/deadlift + contrast ballistic work, 48 h spacing, skill on off-days). The
  closest thing to a published "fighter strength program" with numbers; primary template here.
- **Ruddock et al. 2016** [2] (boxing, SCJ) — squats, deadlifts, Olympic lifts for hip extension, pull-ups,
  dumbbell floor press, plank rows, low-load jump training for RFD, trunk bracing, 2-week taper
  (−40–60 %). Supports the exercise mix and the taper.
- **Turner 2009** (Muay Thai) [12], **Lenetsky & Harris 2012** [13] and **Tack 2013** [14] (MMA),
  **James et al. 2016** [11] — the standard combat-sport S&C literature; all argue for a strength +
  power base. Only abstracts verified for [12][13][14].
- **Suchomel, Nimphius, Stone, Comfort** [4][5][6] — the most-cited modern case for strength-first
  training and weightlifting derivatives in athletes.
- **Joel Jamieson (8WeeksOut)** — the most recognised combat-sport S&C coach; his public interview
  supports ballistic/horizontal power work [22]. His book *Ultimate MMA Conditioning* was **not read**;
  no claim of derivation is made.
- **Not used / not verified:** Phil Daru and other commercial fighter programs (no published primary
  source reached); the ticket's "James et al. 2016, *Towards a determinant-based framework for MMA
  S&C*" does not exist under that title — the real paper is [11].

---

## 8. Seed-key mapping and missing exercises

**In the catalog (verified):** `barbell_back_squat`, `front_squat`, `barbell_bench_press`,
`dumbbell_bench_press`, `pull_up`, `lat_pulldown`, `assisted_pull_up`, `bulgarian_split_squat`,
`ab_wheel_rollout`, `deadlift`, `overhead_press`, `seated_dumbbell_shoulder_press`, `pendlay_row`,
`barbell_row`, `hanging_leg_raise`, `cable_crunch`.

**Missing** (the catalog contains no ballistic, weightlifting, medicine-ball, kettlebell, landmine,
trap-bar, anti-rotation or neck exercise):

| Exercise | Role | Closest catalog substitute | Priority |
|---|---|---|---|
| Box jump (or countermovement jump) | Lower-body plyometric, Routine A #1 | **None** (no jump exists) | **Required** |
| Jump shrug | Pulling derivative, Routine B #1 | None (`barbell_shrug` is not ballistic) | **Required** |
| Medicine-ball chest pass | Upper-body ballistic, Routine A #4 | None (`push_up` is not ballistic) | **Required** |
| Medicine-ball rotational throw | Rotational power, Routine B #5 | None | **Required** |
| Hang power clean | Alternative to jump shrug | Jump shrug (once seeded) | **Required** (sign-off: seeded as the attached alternative) |
| Trap-bar deadlift | Main hinge | `deadlift` | Not seeded (sign-off) — substitute used in [1] |
| Landmine press | Shoulder-friendly press | `overhead_press` / `seated_dumbbell_shoulder_press` | Not seeded (sign-off) |
| Loaded jump squat | Ballistic squat, alt. to box jump | Box jump (once seeded) | Not seeded (sign-off) |
| Pallof press | Anti-rotation trunk | `ab_wheel_rollout` | Not seeded (sign-off) |
| Neck flexion/extension | Optional neck work | None | Dropped (sign-off: weak evidence) |

Each new seed needs localization (en + de), muscle groups (see the coach finding in §4), an
`EquipmentType` decision (§6) and a catalog version bump (`currentVersion` → 3, append-only).
**Shipped (ticket 07, 2026-10-03):** the five required seeds are catalog v3; equipment maps to existing
types (box jump and both medicine-ball throws `.bodyweight`, jump shrug and hang power clean `.barbell`) —
reasoning in `docs/starter-exercise-library.md`, "Catalog v3".

---

## 9. Open questions for later tickets (not decided here)

> **Content sign-off (2026-09-27, wayfinder ticket 06).** (1) Main lifts **3–5**; **jump shrug**
> default with **hang power clean** as its alternative; neck work **dropped**. (2) New seeds are
> exactly the five required ones — `box_jump`, `jump_shrug`, `hang_power_clean`,
> `medicine_ball_chest_pass`, `medicine_ball_rotational_throw`; every optional exercise uses its
> source-backed catalog substitute (`deadlift`, `seated_dumbbell_shoulder_press`, box jump, ab wheel).
> `EquipmentType` cases and the jump shrug / clean muscle groups stay with the seeding ticket.
> (3) One fixed version; phases, taper, power-lift progression, sparring rules and effort are
> program text; a real phase layer is a follow-up (Things). Schedule: A and B each every 7 days,
> offset 3, with a program-text rule "≥ 48 h between A and B — if one slips, push the other back".
> (4) No off-season 3rd day. (6) Decided in ticket 04: free. (5) and (7) remain for design (05).

1. **Content sign-off:** 3–5 vs 3–6 on main lifts; jump shrug vs hang power clean as the default power
   lift; include the optional neck exercise at all?
2. **Seeds:** add the 4 required ballistic seeds (+ which optional ones), with muscle groups that make
   Routine B count as heavy lower body for the conditioning coach; new `EquipmentType` cases or not.
3. **Delivery model:** fixed routines + weekday schedule (Mon/Thu works today) vs a program layer with
   phases, and whether phases should *follow the conditioning program's week* when both are active.
4. **Off-season 3rd day:** worth shipping (would need A/B alternation, not expressible) or text only?
5. **Sparring-day awareness:** reuse the add-on's "I spar hard" flag for a lifting caution, or ask for
   sparring weekdays (the add-on rejected that for itself)?
6. **Monetization:** tier for the program itself and interaction with P1 routine cap / P9 weekday
   schedules / the add-on's `PaywallPlacement.conditioningProgram` — for the monetization ticket.
7. **Safety copy:** plyometric/weightlifting technique notes and "stop if reps slow" — how much text the
   design can carry.

---

## 10. Sources

1. Kostikiadis IN, Methenitis S, Tsoukos A, Veligekas P, Terzis G, Bogdanis GC. The effect of short-term sport-specific strength and conditioning training on physical fitness of well-trained mixed martial arts athletes. *J Sports Sci Med* 2018;17:348–358. PMID 30116107, PMC6090403. Full text read: https://www.jssm.org/volume17/iss3/cap/jssm-17-348.pdf
2. Ruddock AD, Wilson DC, Thompson SW, Hembrough D, Winter EM. Strength and conditioning for professional boxing: recommendations for physical preparation. *Strength Cond J* 2016;38(3):81–90. doi:10.1519/SSC.0000000000000217. Accepted manuscript read: https://shura.shu.ac.uk/11499/
3. Haff GG, Triplett NT (eds). *Essentials of Strength Training and Conditioning* (NSCA), ch. 17 — **read via a CSCS study guide, not the book**: https://www.ptpioneer.com/personal-training/certifications/nsca-cscs/cscs-chapter-17/ ; https://app.achievable.me/study/cscs/learn/program-design-for-resistance-training-training-frequency-exercise-order-and-training-load-and-repetitions
4. Suchomel TJ, Nimphius S, Stone MH. The importance of muscular strength in athletic performance. *Sports Med* 2016;46:1419–1449. doi:10.1007/s40279-016-0486-0
5. Suchomel TJ, Nimphius S, Bellon CR, Stone MH. The importance of muscular strength: training considerations. *Sports Med* 2018;48:765–785. doi:10.1007/s40279-018-0862-z
6. Suchomel TJ, Comfort P, Stone MH. Weightlifting pulling derivatives: rationale for implementation and application. *Sports Med* 2015;45:823–839. doi:10.1007/s40279-015-0314-y
7. Amtmann JA. Self-reported training methods of mixed martial artists at a regional reality fighting event. *J Strength Cond Res* 2004;18:194–196. doi:10.1519/1533-4287(2004)018<0194:STMOMM>2.0.CO;2
8. Rønnestad BR, Nymark BS, Raastad T. Effects of in-season strength maintenance training frequency in professional soccer players. *J Strength Cond Res* 2011;25:2653–2660. doi:10.1519/JSC.0b013e31822dcd96
9. Spiering BA, Mujika I, Sharp MA, Foulis SA. Maintaining physical performance: the minimal dose of exercise needed to preserve endurance and strength over time. *J Strength Cond Res* 2021;35:1449–1458. doi:10.1519/JSC.0000000000003964
10. Loturco I, Nakamura FY, Artioli GG, et al. Strength and power qualities are highly associated with punching impact in elite amateur boxers. *J Strength Cond Res* 2016;30:109–116. doi:10.1519/JSC.0000000000001075
11. James LP, Haff GG, Kelly VG, Beckman EM. Towards a determination of the physiological characteristics distinguishing successful mixed martial arts athletes: a systematic review of combat sport literature. *Sports Med* 2016;46:1525–1551. doi:10.1007/s40279-016-0493-1
12. Turner AN. Strength and conditioning for Muay Thai athletes. *Strength Cond J* 2009;31(6):78–92. doi:10.1519/SSC.0b013e3181b99603 (abstract only)
13. Lenetsky S, Harris N. The mixed martial arts athlete: a physiological profile. *Strength Cond J* 2012;34(1):32–47. doi:10.1519/SSC.0b013e3182389f00 (metadata only)
14. Tack C. Evidence-based guidelines for strength and conditioning in mixed martial arts. *Strength Cond J* 2013;35(5):79–92. doi:10.1519/SSC.0b013e3182a62fef (abstract only — full text paywalled)
15. Beattie K, Ruddock AD. Strength training practices in amateur and professional boxing. *J Strength Cond Res* 2025;39(6):672–679. doi:10.1519/JSC.0000000000005088
16. Cormie P, McGuigan MR, Newton RU. Adaptations in athletic performance after ballistic power versus strength training. *Med Sci Sports Exerc* 2010;42:1582–1598. doi:10.1249/MSS.0b013e3181d2013a
17. Cormie P, McGuigan MR, Newton RU. Influence of strength on magnitude and mechanisms of adaptation to power training. *Med Sci Sports Exerc* 2010;42:1566–1581. doi:10.1249/MSS.0b013e3181cf818d
18. Haff GG, Nimphius S. Training principles for power. *Strength Cond J* 2012;34(6):2–12. doi:10.1519/SSC.0b013e31826db467 (abstract only)
19. Hackett D, Davies T, Soomro N, Halaki M. Olympic weightlifting training improves vertical jump height in sportspeople: a systematic review with meta-analysis. *Br J Sports Med* 2016;50:865–872. doi:10.1136/bjsports-2015-094951
20. Berton R, Lixandrão ME, Pinto e Silva CM, Tricoli V. Effects of weightlifting exercise, traditional resistance and plyometric training on countermovement jump performance: a meta-analysis. *J Sports Sci* 2018;36:2038–2044. doi:10.1080/02640414.2018.1434746
21. de Villarreal ES, Kellis E, Kraemer WJ, Izquierdo M. Determining variables of plyometric training for improving vertical jump height performance: a meta-analysis. *J Strength Cond Res* 2009;23:495–506. doi:10.1519/JSC.0b013e318196b7c6
22. Contreras B. Interview with MMA trainer Joel Jamieson. https://bretcontreras.com/interview-with-mma-trainer-joel-jamieson/ (practitioner opinion, not peer-reviewed)
23. Robinson ZP, Pelland JC, Remmert JF, et al. Exploring the dose-response relationship between estimated resistance training proximity to failure, strength gain, and muscle hypertrophy. *Sports Med* 2024;54:2209–2231. doi:10.1007/s40279-024-02069-2
24. Wilson JM, Marin PJ, Rhea MR, et al. Concurrent training: a meta-analysis examining interference of aerobic and resistance exercises. *J Strength Cond Res* 2012;26:2293–2307. doi:10.1519/JSC.0b013e31823a3e2d
25. Schumann M, Feuerbacher JF, Sünkeler M, et al. Compatibility of concurrent aerobic and strength training for skeletal muscle size and function: an updated systematic review and meta-analysis. *Sports Med* 2022;52:601–612. doi:10.1007/s40279-021-01587-7
26. Sabag A, Najafi A, Michael S, et al. The compatibility of concurrent high intensity interval training and resistance training for muscular strength and hypertrophy: a systematic review and meta-analysis. *J Sports Sci* 2018;36:2472–2483. doi:10.1080/02640414.2018.1464636
27. Robineau J, Babault N, Piscione J, Lacome M, Bigard AX. Specific training effects of concurrent aerobic and strength exercises depend on recovery duration. *J Strength Cond Res* 2016;30:672–683. doi:10.1519/JSC.0000000000000798
28. Williams TD, Tolusso DV, Fedewa MV, Esco MR. Comparison of periodized and non-periodized resistance training on maximal strength: a meta-analysis. *Sports Med* 2017;47:2083–2100. doi:10.1007/s40279-017-0734-y
29. Moesgaard L, Beck MM, Christiansen L, et al. Effects of periodization on strength and muscle hypertrophy in volume-equated resistance training programs: a systematic review and meta-analysis. *Sports Med* 2022;52:1647–1666. doi:10.1007/s40279-021-01636-1
30. Bosquet L, Montpetit J, Arvisais D, Mujika I. Effects of tapering on performance: a meta-analysis. *Med Sci Sports Exerc* 2007;39:1358–1365. doi:10.1249/mss.0b013e31806010e0
31. Travis SK, Mujika I, Gentles JA, Stone MH, Bazyler CD. Tapering and peaking maximal strength for powerlifting performance: a review. *Sports* 2020;8:125. doi:10.3390/sports8090125
32. Bell L, Strafford BW, Coleman M, et al. Integrating deloading into strength and physique sports training programmes: an international Delphi consensus approach. *Sports Med Open* 2023;9:87. doi:10.1186/s40798-023-00633-0

**Verification notes.** Abstracts were read via Europe PMC (PubMed served a captcha). Full texts read:
[1] (JSSM PDF) and [2] (accepted manuscript; its tables are images and were not extracted). Paywalled,
abstract/metadata only: [12][13][14][18]. NSCA figures [3] come from study guides summarising the
*Essentials* textbook, not from the book. Not verified
at source: Jamieson's *Ultimate MMA Conditioning*, Phil Daru's programs, any fighter-specific evidence for
the timing of the last heavy session before a fight.

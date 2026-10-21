# Conditioning progress metrics — research (2026-10-19)

Research for the Things task "History for Conditionining Progress" (`BKey5E9oynXuKXNb1TBeuD`):
which Apple Health / Apple Watch values honestly show conditioning progress for fighters who lift,
and how to read them. Tickets: `.scratch/conditioning-progress/issues/`. Feature doc (once built):
`docs/conditioning-progress.md`; the conditioning feature itself is `docs/fight-conditioning.md`.

**Bottom line.** The assumption that "better conditioning moves these values strongly" is only
partly true. Resting heart rate, heart rate at a fixed workload, heart-rate recovery and VO₂max do
respond — slowly, modestly, and noisily. HRV, SpO₂, respiratory rate and walking heart rate are weak
or non-specific. **SpO₂ is never shown as progress.** Two structural problems for this program:
Apple estimates VO₂max only from outdoor walk/run/hike workouts, and the alactic weeks 9–12 add
little aerobic stimulus, so aerobic markers may plateau there while the athlete is getting fitter.

## Sports science (per metric)

| Metric | Responds to training? | Verdict for the app |
|---|---|---|
| Resting HR | Yes: −2.7 to −5.8 bpm vs. controls with endurance training, more from a higher start; weeks–months ([Reimers 2018](https://www.mdpi.com/2077-0383/7/12/503)) | **Show** as 7-day rolling average vs. the user's own first 2 weeks |
| HR at a fixed, repeated workload | Yes — one of the most useful submaximal monitoring tools ([Buchheit 2014](https://pubmed.ncbi.nlm.nih.gov/24578692/)) | **Show**, but only where the load is really fixed (same session, modality, duration). Bag rounds / sparring have no fixed load |
| Between-interval recovery (identical interval sessions) | Post-exercise recovery improves with adaptation (SMD 0.63) but **also with overreaching** (SMD 0.46) ([Bellenger 2016](https://doi.org/10.1007/s40279-016-0484-2), [Daanen 2012](https://doi.org/10.1123/ijspp.7.3.251)) | Show with care; compare identical protocols only |
| Volume / consistency (sessions, time in target zone) | Counts, not physiology claims | **Show** — the most honest progress signal |
| VO₂max (Apple "Cardio Fitness") | Lab VO₂max rises within 3 weeks, up to ~+18 % in 12 ([Murias 2010](https://elmi.hbku.edu.qa/en/publications/time-course-and-mechanisms-of-adaptations-in-cardiorespiratory-fi/), [Milanović 2015](https://doi.org/10.1007/s40279-015-0365-0), [Gist 2014](https://pubmed.ncbi.nlm.nih.gov/24129784/)); ~half don't respond to moderate training alone ([Sports Med Open 2023](https://link.springer.com/10.1186/s40798-023-00579-3)) | Caveat: watch error 13–16 % MAPE, underestimates fit people ([PLOS One 2025](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12080799/), [JMIR 2024](https://biomedeng.jmir.org/2024/1/e59459)); only from Outdoor Walk/Run/Hike ([Apple](https://support.apple.com/en-gb/HT211856)). Show with "last updated" date + outdoor caveat |
| HRV (Apple stores SDNN) | Small rise with performance gains, but also with overreaching; evidence is ECG RMSSD, Apple is short-window PPG SDNN ([Bellenger 2016](https://doi.org/10.1007/s40279-016-0484-2), [Sensors 2024](https://www.mdpi.com/1424-8220/24/19/6220)) | Recovery/readiness context only, never a fitness score |
| SpO₂ | No: healthy people at sea level are near saturation; no evidence resting SpO₂ rises with training ([review](https://pmc.ncbi.nlm.nih.gov/articles/PMC5008680)); Apple: "not intended for medical use" ([Apple](https://support.apple.com/en-ie/HT211027)) | **Do not show** |
| Respiratory rate, walking HR average | No good evidence as training markers (illness flag; speed/terrain/heat dependent) | **Do not show** |

**Confounders this audience hits hard.** Alcohol raises sleeping HR and suppresses HRV even at low
doses ([Pietilä 2018](https://mental.jmir.org/2018/1/e23)). Weight cuts: 0.9 % / 2.8 % body-mass loss
raised exercise HR by 10 / 18 bpm ([Heaps 1994](https://www.thieme-connect.com/products/ejournals/pdf/10.1055/s-2007-1021023.pdf)),
and HR drift tracks dehydration almost linearly ([Montain & Coyle 1992](https://www.gssiweb.org/en/research/article/influence-of-graded-dehydration-on-hyperthermia-and-cardiovascular-drift-during-exercise-)) —
during a cut every HR metric looks like lost fitness. Also illness, heat, sleep, stress.

**Smoothing and minimum data.** Weekly / 7-day rolling averages ([Plews 2012](https://pubmed.ncbi.nlm.nih.gov/22367011/));
≥ 3 valid readings per week; judge changes against measurement error / smallest meaningful change
([Buchheit 2014](https://pubmed.ncbi.nlm.nih.gov/24578692/)); no trend statement before ~4 weeks
(ideally 6–8). Single-session cardiac drift needs ~10 sessions to be reliable and, without pace or
power, mostly reflects heat and hydration ([Barsumyan 2025](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12271085/), n = 20, cycling) — **not shipped**.

**Program-phase caveat.** 5–8 s alactic sprints with long rests are not the 30 s sprint protocols
of the meta-analyses: aerobic markers may plateau in weeks 9–12. The UI should say this is expected.

## Copy rules

- **May say:** "Your 7-day resting heart rate is down X bpm since week 1", "Same session, lower
  heart rate", "Trends like these often reflect improved aerobic fitness", "Estimates from Apple Watch".
- **Never:** anything implying heart/lung health or diagnosis ("healthier heart", any SpO₂
  interpretation); guarantees ("this program raises your VO₂max"); that falling HRV or rising HR means
  overtraining or illness; that VO₂max is lab-accurate.
- Always attribute to Apple Watch estimates, note that sleep, alcohol, heat, illness and weight cuts
  move them, and that this is not medical advice. Consistent with the marketing-claims rules in
  `docs/fight-conditioning.md`.

## Apple Health / HealthKit (verified 2026-10-19, installed iOS 26 SDK + Apple docs)

**Per-session heart rate.**
- Find the workout with `HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: [id])`
  — the id is `ConditioningRecord.id` / `MatSession` id (see `docs/fight-conditioning.md`).
- Fetch its HR with `HKQuery.predicateForObjects(from: workout)` (samples `HKLiveWorkoutBuilder`
  linked to the workout). A time-window predicate also catches passive readings and other apps —
  fallback only. ([Adding samples to a workout](https://developer.apple.com/documentation/healthkit/adding-samples-to-a-workout))
- **Use `HKStatisticsCollectionQueryDescriptor`** (`.discreteAverage/.discreteMin/.discreteMax`,
  anchor = workout start, interval 5–10 s): downsamples for the chart *and* handles HealthKit's
  condensing of workout HR older than a few months (merged samples with `count > 1`), which a plain
  sample query would mis-read. ([Accessing condensed workout samples](https://developer.apple.com/documentation/healthkit/accessing-condensed-workout-samples),
  [descriptor](https://developer.apple.com/documentation/healthkit/hkstatisticscollectionquerydescriptor/init(predicate:options:anchordate:intervalcomponents:)))
- Watch density ≈ 1 sample / 5 s during a workout (empirical, [forum 724724](https://developer.apple.com/forums/thread/724724)).
- Headline numbers: `HKWorkout.statistics(for: heartRate)` → average/min/max; `nil` when nothing is
  linked ([doc](https://developer.apple.com/documentation/healthkit/hkworkout/statistics(for:))).
- **iPhone-run sessions have no HR** (zero samples, no sensor) → the design's no-HR state.
- **Watch → iPhone sync lag:** linked samples can reach the phone *after* the workout. Zero samples
  for a watch-sourced workout is not final — show a "syncing from Apple Watch" state and re-query.

**Progress metrics.** All read-only; new read types beyond today's (dateOfBirth, restingHeartRate,
heartRate) must be requested on demand and named in `NSHealthShareUsageDescription` (en + de).

| Type | Unit | Produced by / caveat |
|---|---|---|
| `restingHeartRate` | count/min | System, ~daily; earlier same-day values may be replaced |
| `vo2Max` | ml/(kg·min) | Watch S3+, only Apple Workout-app Outdoor Walk/Run/Hike; range 14–65. Our rowing/bike/HIIT/mat sessions never contribute ([doc](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/vo2max)) |
| `heartRateRecoveryOneMinute` | count/min | Not documented for third-party sessions; reportedly often absent → **don't rely on it** |
| `heartRateVariabilitySDNN` | ms | Watch, several/day, irregular |
| `oxygenSaturation` | % | US S9/S10/Ultra 2: computed on iPhone only. Not shown (see above) |
| `workoutEffortScore` / `estimatedWorkoutEffortScore` | appleEffortScore | Estimated only for walk/run/hike/cycle and reportedly unseen even then ([forum 764884](https://developer.apple.com/forums/thread/764884)) — not used |

Trends: `HKStatisticsCollectionQueryDescriptor`, `.discreteAverage` / `.mostRecent`,
`DateComponents(day: 7)` or `(month: 1)`, anchored Monday 03:00
([Apple example](https://developer.apple.com/documentation/healthkit/executing-statistics-collection-queries)).

**Swift 6.** In the installed iOS 26 SDK `HKHealthStore`, `HKWorkout`, `HKQuantitySample`,
`HKQuantity`, `HKStatistics`, `HKStatisticsCollection` and the query result handlers are
`NS_SWIFT_SENDABLE` — not the WatchConnectivity trap. Still: async descriptors, `@concurrent` on the
concrete Data method, project to plain `(Date, bpm)` value structs before Presentation.

**iOS 27 / watchOS 27 workout zones (not used yet).** `HKWorkout.zoneGroupsByType`
(time-in-zone computed automatically for `HKLiveWorkoutBuilder` workouts),
`HKHealthStore.preferredWorkoutZoneConfiguration(for:)`, `HKWorkoutBuilder.setCustomZoneConfiguration`
([Accessing workout zone data](https://developer.apple.com/documentation/healthkit/accessing-workout-zone-data),
[WWDC26 207](https://developer.apple.com/videos/play/wwdc2026/207/)). Not in the installed SDK, and
the app targets iOS 26.1 — so v1 computes zones itself from `HeartRateProfile`. Follow-up once on
Xcode 27: `#available(iOS 27, *)` read of the user's Health zones so both agree; backfill for
pre-27 workouts is undocumented.

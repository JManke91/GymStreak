# App Store Marketing Copy — v1.1.19

## Hold-gates resolved

- **History import from Strong and Hevy** (`app-store-subtitle-keywords.md` §3 hold-gate, "rides the first App Store version after 1.1.18"): **released by this release.** Both imports are in the 1.1.19 build, so "bring your Strong or Hevy history" may now be claimed, free and without a Pro qualifier. The §3 note now reads "live as of v1.1.19".
- **Round-timer keyword rotation** (`app-store-subtitle-keywords.md` §4.2c / §5.2b, "enter with the version that carries the round timer"): **gate satisfied by this release.** The round timer ships in 1.1.19 (iPhone and watch, free). The proposals are still not entered. Entering them is a deliberate separate pass, so see the flag below. Only the status lines were updated.
- **v1.1.18 promotional text** ("paste once 1.1.18 is live"): **superseded** by the line below once 1.1.19 is live.
- **Pending v1.1.18 description paste** (`app-store-description.md`, conditioning + programs): not a feature hold. It is still the baseline the edit below builds on. If it was never pasted, paste it together with the edit below.

## Promotional Text (paste now — no build required)

Paste this only once v1.1.19 is live. 1.1.18 has neither the import nor the round timer.

### English (en-US) — 164/170
New: bring your workout history from Strong or Hevy, free, into your progress charts and PRs. Plus a round timer for sparring on iPhone and Apple Watch. No account.

### German (de-DE) — 169/170
Neu: Importiere deine Workouts aus Strong oder Hevy kostenlos in Verlauf, Diagramme und Rekorde. Dazu ein Rundentimer fürs Sparring auf iPhone & Apple Watch. Ohne Konto.

Previously live (v1.1.18):
- en-US (145/170): `New: free training programs. Add Beginner Full Body, Push / Pull / Legs or Fighter Strength in one tap, planned around your recovery. No account.`
- de-DE (167/170): `Neu: kostenlose Trainingsprogramme. Füge Ganzkörper für Einsteiger, Push / Pull / Legs oder Fighter Strength per Tipp hinzu – nach deiner Erholung geplant. Ohne Konto.`

Why import leads: it speaks to the largest group of prospective users, lifters already on Strong or Hevy. It also removes their one reason not to switch (acquisition lever #16), and it is free and uncapped (monetization §3 Rule 4). The round timer comes second. It serves a narrower fighter audience, which the keyword rotation targets separately. Claim checks: only Strong and Hevy are named, and the line says "workout history" / "Workouts" (§3). Imported workouts do reach History, the progress charts and records (WhatToTest 1.1.19). The round timer runs on both iPhone and watch and is free (`docs/fight-conditioning.md` "Round timer"). "Gong" was left out of the German line on purpose: the watch signals rounds with haptics, not a bell. The no-account promise stays, and there is no subscription claim.

## Description — proposed edit

Reason: the import hold-gate was released (above), and 1.1.19 adds a free round timer that belongs in the conditioning section. No caps changed. `ProFeatureCaps.swift` holds the same limits as at v1.1.18 (3 routines, coach tasters 5/1/1, max-weight chart, 1W/1M/3M, conditioning weeks 1–4), so no existing claim became false. Import, round timer and mat sessions are all free. Mat sessions are deliberately not mentioned, because there was no room, and logging a session is the weakest of the three as a selling point.

**Baseline:** the v1.1.18 edit from `AppStore/Marketing.1.1.18.md` applied to the blocks in `app-store-description.md` (EN 3,978 / DE 3,985 by `sed -n '<block>p' | wc -m`, trailing newline included). This edit rides the next version submission, which is **1.1.20's binary**.

### English (en-US) — 3978 → 3993/4000 (3,992 in the field, 8 characters of headroom)

1. Conditioning paragraph: `…paced to your own heart-rate zones — plus a 12-week program built around your lifting.` → `…paced to your own heart-rate zones, a round timer for sparring, and a 12-week program built around your lifting.`
2. `MAKE PROGRESS VISIBLE`: after `– Training volume (weight × reps)` add a new line: `Switching from Strong or Hevy? Import your workout history, free.`
3. Trims:
   - `– Add, remove, or swap in an alternative exercise when a machine is taken` → `– Add, remove, or swap exercises when a machine is taken`
   - `…routine template after every workout, so your plan always reflects your current level.` → `…routine template after every workout.`
   - `Every workout syncs seamlessly with Apple Health` → `Every workout syncs with Apple Health`

### German (de-DE) — 3985 → 3983/4000 (3,982 in the field, 18 characters of headroom)

The German additions did not fit without trims (+64 characters against 16 of headroom), so these four trims pay for them.

1. Conditioning paragraph: `…nach deinen Herzfrequenzzonen – plus ein 12-Wochen-Programm rund um dein Krafttraining.` → `…nach deinen Herzfrequenzzonen, ein Rundentimer fürs Sparring und ein 12-Wochen-Programm rund um dein Krafttraining.`
2. `FORTSCHRITT SICHTBAR MACHEN`: after `– Trainingsvolumen (Gewicht × Wiederholungen)` add a new line: `Kommst du von Strong oder Hevy? Importiere deinen Verlauf kostenlos.`
3. Trims:
   - `– Übungen hinzufügen, entfernen oder gegen eine Alternative tauschen, wenn die Maschine besetzt ist` → `– Übungen hinzufügen, entfernen oder tauschen`
   - `– Tiefenanalyse einzelner Übungen und ihrer Entwicklung` → `– Tiefenanalyse einzelner Übungen`
   - `…dein Wochenziel passt sich automatisch an.` → `…dein Wochenziel passt sich an.`
   - `Über iCloud sind deine Daten auf allen Geräten sicher und aktuell.` → `Über iCloud sind deine Daten auf allen Geräten aktuell.`

How it was measured: every replacement was applied to the v1.1.18 baseline with exact-match-once string replacement, then counted with `wc -m`.

## Subtitle & Keyword Field — flag

The §8 reason is that a proposed rotation's precondition is now met. §4.2c (en-US: out `private`, `1rm`, `ai`; in `timer`, `round`, `bjj`, 100/100) and §5.2b (de-DE: out `offline`, `watch`, `1rm`; in `kampfsport`, `timer`, 98/100) were written "to be entered with the version that ships the round timer". That version is 1.1.19, so the rotation is now due. Like any keyword edit, it rides a version submission. The App Name and subtitles are unchanged, so no subtitle action is needed, and no §3 claim became false. The first search-term report (due ~2026-10-07 after 1.1.16) is the evidence to check `boxing` / `round` vs `kampfsport` against before entering. §3 still lacks the round timer and mat sessions (and Programs, per v1.1.18), so add them there at the same time. Rotate deliberately in a separate pass, against the swap benches in §4.2 / §5.2 / §6.5.

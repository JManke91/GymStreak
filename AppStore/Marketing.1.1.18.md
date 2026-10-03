# App Store Marketing Copy — v1.1.18

## Hold-gates resolved

- **Conditioning description section** (proposed in `Marketing.1.1.17.md`, staged to ride the 1.1.18 submission): **released by this release.** It is carried into the description edit below as step A, together with its trims. It was never written into `app-store-description.md`, so the doc still shows the pre-conditioning text.
- **v1.1.17 conditioning promotional text** ("paste once 1.1.17 is live"): **superseded.** It stays valid while 1.1.17 is the live build. Replace it with the line below once 1.1.18 is live.
- **Apple Calendar sync**: already live as of v1.1.14 (resolved in the v1.1.17 pass). No change.

## Promotional Text (paste now — no build required)

Paste this only once v1.1.18 is live. It leads with Programs, which 1.1.17 does not have.

### English (en-US) — 145/170
New: free training programs. Add Beginner Full Body, Push / Pull / Legs or Fighter Strength in one tap, planned around your recovery. No account.

### German (de-DE) — 167/170
Neu: kostenlose Trainingsprogramme. Füge Ganzkörper für Einsteiger, Push / Pull / Legs oder Fighter Strength per Tipp hinzu – nach deiner Erholung geplant. Ohne Konto.

Previously live / recommended (v1.1.17):
- en-US (164/170): `New: conditioning for fighters. Interval and aerobic sessions paced to your own heart-rate zones on iPhone and Apple Watch, planned around your lifting. No account.`
- de-DE (161/170): `Neu: Kondition für Kampfsportler. Intervall- und Ausdauereinheiten nach deinen Herzfrequenzzonen auf iPhone & Apple Watch, passend zum Krafttraining. Ohne Konto.`

Why Programs lead: they are the biggest 1.1.18 feature and they need no Apple Intelligence hardware. They also answer the beginner's first question, "what do I train?", which the double-progression pitch assumes is already settled. "Free" is accurate: programs are free and do not count against `ProFeatureCaps.freeRoutineLimit` (WhatToTest 1.1.18, `docs/routine-programs.md`). "Planned around your recovery" refers to the optional recovery-time scheduling the install sheet offers.

## Description — proposed edit

Reason: two changes are due. First, the conditioning section staged in v1.1.17 (hold released above). Second, v1.1.18 adds free ready-made programs, which belong in the routines section. No caps changed (`ProFeatureCaps.swift` is unchanged since v1.1.17), so no existing claim became false. "3 are free" still holds, because programs do not use routine slots.

Paste this into the **1.1.18** version page if it has not been submitted for review yet. Otherwise it rides 1.1.19's submission.

### English (en-US) — 3898 → 3977/4000

**A. Conditioning (carried from v1.1.17, unchanged):**
1. Insert after the `PLAN YOUR WEEK` paragraph (before `APPLE HEALTH & ICLOUD`):
   ```
   CONDITIONING FOR FIGHTERS
   Interval and aerobic sessions on iPhone and Apple Watch, paced to your own heart-rate zones — plus a 12-week program built around your lifting.
   ```
2. In the Pro list, after `– Unlimited AI Coach chat, recaps and exercise deep-dives`, add `– Phases 2 and 3 of the 12-week conditioning program`.
3. Trims: remove ` One tap, and your plan grows with your strength.`; `…next set — even when the app is in the background.` → `…next set.`; remove the closing line `Download GymStreak and start your best training today.` (and its blank line).

**B. Programs (new):**
4. Routines paragraph: `…exactly the way your training demands.` → `…exactly the way your training demands. Or start from a free ready-made program like Push / Pull / Legs.`
5. Trims to make room:
   - AI Coach: `…with Apple Intelligence and gives you clear, fact-based insights:` → `…with Apple Intelligence:`
   - Apple Watch: `– Reliable recovery: even if the app is terminated, your active workout is never lost` → `– Your active workout is never lost, even if the app is closed`

### German (de-DE) — 3983 → 3984/4000

**A. Conditioning (carried from v1.1.17, unchanged):**
1. Insert after the `PLANE DEINE WOCHE` paragraph (before `APPLE HEALTH & ICLOUD`):
   ```
   KONDITION FÜR KAMPFSPORTLER
   Intervall- und Ausdauereinheiten auf iPhone und Apple Watch, nach deinen Herzfrequenzzonen – plus ein 12-Wochen-Programm rund um dein Krafttraining.
   ```
2. In the Pro list, after `– Unbegrenzten KI-Coach-Chat, Rückblicke und Tiefenanalysen`, add `– Phase 2 und 3 des 12-Wochen-Konditionsprogramms`.
3. Trims: `…Pausenzeit – genau so, wie dein Training es verlangt.` → `…Pausenzeit.`; `Trainiere unabhängig vom iPhone. Deine Routinen synchronisieren sich automatisch, du bekommst volles Tracking am Handgelenk:` → `Trainiere unabhängig vom iPhone – mit vollem Tracking am Handgelenk:`; `…Routinenvorlage – so spiegelt dein Plan immer deinen aktuellen Stand.` → `…Routinenvorlage.`; remove the closing line `Lade GymStreak herunter und starte noch heute dein bestes Training.` (and its blank line).

**B. Programme (new):**
4. Routines paragraph: `…Pausenzeit.` (after trim A3) → `…Pausenzeit. Oder starte mit einem fertigen Programm wie Push / Pull / Legs – kostenlos.`
5. Trims to make room:
   - KI-Coach: `…mit Apple Intelligence und liefert dir klare, faktenbasierte Auswertungen:` → `…mit Apple Intelligence:`
   - Apple Watch: `– Zuverlässige Wiederherstellung: Dein laufendes Workout geht nie verloren` → `– Dein laufendes Workout geht nie verloren`

German headroom after both edits: **16 characters**. Any further German addition needs another trim first.

Lengths were measured by applying every replacement above to the code blocks in `app-store-description.md` (Python `len`, which matches `wc -m`). The doc's 3,899/3,984 figures include a trailing newline.

## Subtitle & Keyword Field — no action (one pending input)

The App Name, subtitles and caps are unchanged, so no §3 claim became false. The first search-term report is **not yet available**: 1.1.16 went live around 2026-09-09, so the report is due around **2026-10-07**, a few days from now. It remains the input to the next rotation (§8).

New input for that rotation: Programs make `program`, `split`, `ppl` and `push pull legs` truthful claims. `program` already sits in the en-GB/en-AU fields and on the swap benches. §3 (feature basis) does not list Programs yet. Add them there when the rotation happens. Rotate deliberately in a separate pass, against the swap benches in §4.2 / §5.2 / §6.5.

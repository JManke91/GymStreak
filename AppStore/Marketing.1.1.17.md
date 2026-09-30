# App Store Marketing Copy — v1.1.17

## Hold-gates resolved

- **Apple Calendar sync** (description paragraph and free-list mention in `app-store-description.md`, calendar variants in `app-store-promotional-text.md`, paste warning in `app-store-connect-actions.md`): **already released.** The feature shipped in **v1.1.14** (live 2026-09-04, CHANGELOG `[1.1.14]`), so the gate has been satisfied since then; the "hold until live" notes were never updated. They now read "live as of v1.1.14". The calendar copy is safe to paste.

## Promotional Text (paste now — no build required)

Paste this only once v1.1.17 is live. It leads with conditioning, which the installed 1.1.16 build does not have.

### English (en-US) — 164/170
New: conditioning for fighters. Interval and aerobic sessions paced to your own heart-rate zones on iPhone and Apple Watch, planned around your lifting. No account.

### German (de-DE) — 161/170
Neu: Kondition für Kampfsportler. Intervall- und Ausdauereinheiten nach deinen Herzfrequenzzonen auf iPhone & Apple Watch, passend zum Krafttraining. Ohne Konto.

Previously live:
- en-US (165/170): `Stop guessing your next weight. GymStreak spots when you've earned the jump, coaches you with private on-device AI, and tracks every set from your wrist. No account.`
- de-DE (163/170): `Nie wieder raten, welches Gewicht als Nächstes kommt: GymStreak erkennt fällige Steigerungen, coacht dich privat auf dem Gerät und trackt jeden Satz am Handgelenk.`

Why conditioning is the lead, and not Coach routine drafting: conditioning needs no Apple Intelligence hardware, so it is true for every user. An AI lead would need the hardware qualifier (§3 of `app-store-subtitle-keywords.md`). Only single sessions and Phase 1 of the program are free. The copy promises the sessions and the program, not "free", so Phases 2–3 being Pro does not make it false.

## Description — proposed edit

Reason: v1.1.17 adds conditioning for fighters, a user-facing capability big enough for its own section. It also adds a new Pro unit (Phases 2–3 of the 12-week program, `ProFeatureCaps.freeConditioningProgramWeeks = 4`), and the Pro list should name it. No existing claim became false: "Tracking is free and unlimited" still holds, because single sessions, the watch runner and Phase 1 are free.

This edit rides a version submission, so it goes live with **1.1.18's** binary, not today's.

### English (en-US) — 3899 → 3977/4000

1. Insert after the `PLAN YOUR WEEK` paragraph (before `APPLE HEALTH & ICLOUD`):
   ```
   CONDITIONING FOR FIGHTERS
   Interval and aerobic sessions on iPhone and Apple Watch, paced to your own heart-rate zones — plus a 12-week program built around your lifting.
   ```
2. In the Pro list, after `– Unlimited AI Coach chat, recaps and exercise deep-dives`, add:
   ```
   – Phases 2 and 3 of the 12-week conditioning program
   ```
3. Trims to make room:
   - Progressive overload: remove ` One tap, and your plan grows with your strength.`
   - Live Activities: `…next set — even when the app is in the background.` → `…next set.`
   - Remove the closing line `Download GymStreak and start your best training today.` (and its blank line).

### German (de-DE) — 3984 → 3992/4000

German had 16 characters of headroom, so this edit needs three trims.

1. Insert after the `PLANE DEINE WOCHE` paragraph (before `APPLE HEALTH & ICLOUD`):
   ```
   KONDITION FÜR KAMPFSPORTLER
   Intervall- und Ausdauereinheiten auf iPhone und Apple Watch, nach deinen Herzfrequenzzonen – plus ein 12-Wochen-Programm rund um dein Krafttraining.
   ```
2. In the Pro list, after `– Unbegrenzten KI-Coach-Chat, Rückblicke und Tiefenanalysen`, add:
   ```
   – Phase 2 und 3 des 12-Wochen-Konditionsprogramms
   ```
3. Trims to make room:
   - Routines: `…Pausenzeit – genau so, wie dein Training es verlangt.` → `…Pausenzeit.`
   - Apple Watch: `Trainiere unabhängig vom iPhone. Deine Routinen synchronisieren sich automatisch, du bekommst volles Tracking am Handgelenk:` → `Trainiere unabhängig vom iPhone – mit vollem Tracking am Handgelenk:`
   - Templates: `…Routinenvorlage – so spiegelt dein Plan immer deinen aktuellen Stand.` → `…Routinenvorlage.`
   - Remove the closing line `Lade GymStreak herunter und starte noch heute dein bestes Training.` (and its blank line).

The German result has only 8 characters of headroom. Any further German addition needs another trim first.

Not proposed: Coach routine drafting and training reminders. Drafting needs Apple Intelligence and fits under the existing AI Coach section's promise. Reminders are a retention feature, not a reason to install. Neither fits the German character budget.

## Subtitle & Keyword Field — no action (one pending input)

The App Name, subtitles and §3 feature basis claims are unchanged, and no cap change made any §3 claim false. **The search-term report is now due.** 1.1.16 went live around 2026-09-09. The first report becomes available about four weeks later, so around **2026-10-07**, and it is the input to the next rotation (§8). Read it per storefront. Then rotate deliberately in a separate pass, against the swap benches in §4.2 / §5.2 / §6.5.

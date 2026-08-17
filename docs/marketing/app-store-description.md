# App Store Description

Full App Store description copy for the GymStreak listing, per storefront locale. This is the text for the App Store **Description** field.

Notes:
- On the Apple App Store the description is **not indexed for search** — it is a pure conversion asset. No keyword stuffing; the first ~2 lines must sell before the "Read More" / "Weiterlesen" fold.
- English is ~3,760 characters and German ~3,970 — both under the 4,000 limit, but German now has little headroom: the Pro block added at launch spent most of it, and several sentences were tightened to make room. Re-measure before adding anything to the de version.
- German uses ß and umlauts (de-DE storefront).
- **AI Coach** requires Apple Intelligence (iOS 26+, supported hardware) — phrasing kept accurate ("on-device" / "auf dem Gerät").
- **Updated 2026-08-17 for the Pro launch (ticket 15 / `docs/pro-subscription.md` §9.6).** The "completely subscription-free" / "ganz ohne Abo" and "No account, no subscription" / "Kein Konto, kein Abo" claims are gone: leaving them live next to a paywall is a review-guideline risk and, per `monetization-strategy.md` §1, a guaranteed one-star generator. **This copy and the `ProGating.shippedValue` flip are one release or neither** — and if the kill switch is ever flipped back off, this copy has to be reverted with it.
- The no-**account** promise is untouched and still stated, because it is still true. Only the no-**subscription** claim was false after launch.
- **Lifetime is deliberately not mentioned.** It is deferred past the launch submission (decided 2026-08-17): the SKU does not exist in App Store Connect, and a first non-consumable needs its own version submission. Add it to the subscription block below in the release that ships it.
- The subscription block at the end carries the title, duration and price that App Review Guideline 3.1.2 expects to find in the metadata; keep it in sync with `monetization-strategy.md` §6 if pricing changes.

---

## English (en-US)

```
Your strength training deserves an app that works as hard as you do. GymStreak is your native workout tracker for iPhone and Apple Watch — fast, private, and account-free. Track unlimited workouts free; Pro unlocks unlimited routines and full analytics.

YOUR ROUTINES. YOUR PLAN. YOUR PROGRESS.
Build tailored training routines from a rich exercise library spanning 20+ muscle groups. Configure every set with reps, weight, and rest — exactly the way your training demands.

YOUR AI COACH — RIGHT ON YOUR DEVICE
GymStreak analyzes your own training data with Apple Intelligence and gives you clear, fact-based insights:
– A short recap right after every workout
– A review across the week, month, or year
– A deep-dive into how each exercise is progressing
– A comparison of every workout against your previous session
Everything is computed entirely on your iPhone. Your data never leaves your device.

PROGRESSIVE OVERLOAD THAT THINKS AHEAD
Set a rep range for any exercise (e.g. 8–12). Once you hit the top of the range across every set, GymStreak automatically suggests a weight increase — following the proven Double Progression model. One tap, and your plan grows with your strength.

SUPERSETS FOR MAXIMUM INTENSITY
Combine exercises into supersets. GymStreak detects your rounds automatically and only starts the rest timer once every exercise in a round is done.

APPLE WATCH — FULLY STANDALONE
Train completely independently of your iPhone. Your routines sync automatically, and you get full tracking right on your wrist:
– Real-time heart rate and calories
– Complete sets with the Action Button (Apple Watch Ultra) or Double Tap
– Automatic finish after your final set
– Completed workouts transfer to your iPhone automatically
– Reliable recovery: even if the app is terminated, your active workout is never lost

INTELLIGENT WORKOUT TRACKING
Start a workout straight from your routine and track every set in real time:
– Automatic rest timer between sets
– Adjust reps and weight right inside the workout
– Add, remove, or swap in an alternative exercise when a machine is taken
– Workout summary with duration, volume, and calories

LIVE ACTIVITIES & DYNAMIC ISLAND
Your rest timer runs right on the Lock Screen and in the Dynamic Island. A notification brings you back in time for the next set — even when the app is in the background.

MAKE PROGRESS VISIBLE
Track your development with interactive charts:
– Max weight
– Estimated 1RM (one-rep max)
– Training volume (weight × reps)

TEMPLATES THAT GROW WITH YOU
Push your adjustments back into the routine template after every workout, so your plan always reflects your current level.

PLAN YOUR WEEK
Schedule your routines by cadence or on fixed weekdays. Your weekly goal adapts automatically to your plan.

APPLE HEALTH & ICLOUD
Every workout syncs seamlessly with Apple Health and contributes to your activity rings. With iCloud, your data stays safe and up to date across all your devices.

PRIVACY FIRST
No account, ever. Your training data belongs to you and syncs only through your personal iCloud account — we never see it.

FREE, AND GYMSTREAK PRO
Tracking is free and unlimited: workouts, sets, the Apple Watch app, supersets, rest timers, Apple Health and iCloud sync. Nothing you have already created is ever taken away.
Pro adds:
– Unlimited routines (3 are free)
– Full analytics: estimated 1RM, volume, 1-year and all-time ranges
– Fixed weekday scheduling
– Unlimited AI Coach chat, recaps and exercise deep-dives

Pro is $4.99/month or $24.99/year, with a 7-day free trial on the yearly plan. It renews automatically unless cancelled at least 24 hours before the period ends; manage or cancel any time in Settings.

Download GymStreak and start your best training today.
```

---

## German (de-DE)

```
Dein Krafttraining verdient eine App, die so hart arbeitet wie du. GymStreak ist dein nativer Workout-Tracker für iPhone und Apple Watch – schnell, privat und ohne Konto. Track unbegrenzt viele Workouts kostenlos; Pro schaltet unbegrenzte Routinen und alle Auswertungen frei.

DEINE ROUTINEN. DEIN PLAN. DEIN FORTSCHRITT.
Erstelle maßgeschneiderte Routinen aus einer Übungsbibliothek mit über 20 Muskelgruppen. Konfiguriere jeden Satz mit Wiederholungen, Gewicht und Pausenzeit – genau so, wie dein Training es verlangt.

DEIN KI-COACH – DIREKT AUF DEM GERÄT
GymStreak analysiert deine Trainingsdaten mit Apple Intelligence und liefert dir klare, faktenbasierte Auswertungen:
– Kurzes Recap direkt nach jedem Workout
– Rückblick über Woche, Monat oder Jahr
– Tiefenanalyse einzelner Übungen und ihrer Entwicklung
– Vergleich jedes Workouts mit deiner letzten Einheit
Alles wird auf deinem iPhone berechnet. Deine Daten verlassen nie dein Gerät.

PROGRESSIVE OVERLOAD, DIE MITDENKT
Lege für jede Übung einen Wiederholungsbereich fest (z. B. 8–12). Sobald du in allen Sätzen das obere Limit erreichst, schlägt dir GymStreak automatisch eine Gewichtssteigerung vor – nach dem Prinzip der Double Progression.

SUPERSÄTZE FÜR MAXIMALE INTENSITÄT
Kombiniere Übungen zu Supersätzen. GymStreak erkennt deine Runden automatisch und startet den Pausentimer erst, wenn die Runde komplett ist.

APPLE WATCH – VÖLLIG EIGENSTÄNDIG
Trainiere unabhängig vom iPhone. Deine Routinen synchronisieren sich automatisch, du bekommst volles Tracking am Handgelenk:
– Herzfrequenz und Kalorien in Echtzeit
– Sätze per Action Button (Apple Watch Ultra) oder Double Tap abschließen
– Automatischer Abschluss nach dem letzten Satz
– Abgeschlossene Workouts werden automatisch an dein iPhone übertragen
– Zuverlässige Wiederherstellung: Dein laufendes Workout geht nie verloren

INTELLIGENTES WORKOUT-TRACKING
Starte ein Workout direkt aus deiner Routine und tracke jeden Satz in Echtzeit:
– Automatischer Pausentimer zwischen den Sätzen
– Wiederholungen und Gewicht direkt im Workout anpassen
– Übungen hinzufügen, entfernen oder gegen eine Alternative tauschen, wenn die Maschine besetzt ist
– Workout-Zusammenfassung mit Dauer, Volumen und Kalorien

LIVE ACTIVITIES & DYNAMIC ISLAND
Dein Pausentimer läuft direkt auf dem Sperrbildschirm und in der Dynamic Island. Eine Benachrichtigung holt dich rechtzeitig zum nächsten Satz zurück.

FORTSCHRITT SICHTBAR MACHEN
Verfolge deine Entwicklung mit interaktiven Charts:
– Maximales Gewicht
– Geschätztes 1RM (One-Rep Maximum)
– Trainingsvolumen (Gewicht × Wiederholungen)

VORLAGEN, DIE MIT DIR WACHSEN
Übernimm deine Anpassungen nach jedem Workout direkt in die Routinenvorlage – so spiegelt dein Plan immer deinen aktuellen Stand.

PLANE DEINE WOCHE
Plane deine Routinen nach Rhythmus oder festen Wochentagen – dein Wochenziel passt sich automatisch an.

APPLE HEALTH & ICLOUD
Jedes Workout wird mit Apple Health synchronisiert und trägt zu deinen Aktivitätsringen bei. Über iCloud sind deine Daten auf allen Geräten sicher und aktuell.

PRIVATSPHÄRE AN ERSTER STELLE
Kein Konto, niemals. Deine Trainingsdaten gehören dir und werden ausschließlich über dein persönliches iCloud-Konto synchronisiert – wir bekommen sie nie zu sehen.

KOSTENLOS UND GYMSTREAK PRO
Tracken ist kostenlos und unbegrenzt: Workouts, Sätze, Apple-Watch-App, Supersätze, Pausentimer, Apple Health und iCloud-Sync. Was du angelegt hast, wird dir nie weggenommen.
Pro ergänzt:
– Unbegrenzt viele Routinen (3 sind kostenlos)
– Alle Auswertungen: 1RM, Volumen, Zeiträume 1 Jahr und gesamt
– Feste Wochentag-Planung
– Unbegrenzten KI-Coach-Chat, Rückblicke und Tiefenanalysen

Pro kostet 4,99 €/Monat oder 24,99 €/Jahr, im Jahresabo mit 7 Tagen kostenlos. Das Abo verlängert sich automatisch, sofern nicht mindestens 24 Stunden vor Ende der Periode gekündigt wird; jederzeit in den Einstellungen kündbar.

Lade GymStreak herunter und starte noch heute dein bestes Training.
```

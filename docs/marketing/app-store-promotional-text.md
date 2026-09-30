# App Store Promotional Text

Short promotional copy for the App Store **Promotional Text** field (the line shown above the description; **max 170 characters**, editable without a new build).

Each option below is within the 170-character limit. Pick one per locale, or rotate them.

**See also `docs/marketing/app-store-subtitle-keywords.md`** — a 2026-08-25 ASO pass that adds
the Subtitle and Keyword Field, plus a promotional-text set written to complement them (it avoids
re-spending tokens the title and subtitle already index). Prefer that set when the subtitle and
keyword field from that doc are live; the variants below predate them.

**Updated 2026-08-17 for the Pro launch (ticket 15 / `docs/pro-subscription.md` §9.6).** Every option previously ended on "no account, no subscription" / "ohne Konto, ohne Abo". The no-**subscription** half is no longer true and had to go from every variant — including the ones not currently live, because this field is edited without a build and a stale variant can be pasted back months later. The no-**account** promise stays: it is still true.

**Current recommendation (2026-09-30, v1.1.17)** — paste once 1.1.17 is live; it leads with the
conditioning feature that build ships (`AppStore/Marketing.1.1.17.md` has the reasoning):

- en-US (164/170): `New: conditioning for fighters. Interval and aerobic sessions paced to your own heart-rate zones on iPhone and Apple Watch, planned around your lifting. No account.`
- de-DE (161/170): `Neu: Kondition für Kampfsportler. Intervall- und Ausdauereinheiten nach deinen Herzfrequenzzonen auf iPhone & Apple Watch, passend zum Krafttraining. Ohne Konto.`

---

## English (en-US)

Primary (recommended):
```
Native workout tracker for iPhone & Apple Watch. Private on-device AI Coach, progressive overload, supersets — track unlimited workouts free, no account.
```

Alternatives:
```
Train harder with a private AI Coach, automatic progressive overload, and full standalone Apple Watch tracking. No account. Unlimited workout tracking, free.
```

```
Your routines, supersets, and rest timers — with a private on-device AI Coach and Apple Watch that tracks every set. Track unlimited workouts free.
```

Calendar-sync variant — **live as of v1.1.14**, safe to paste:
```
Your training plan, right in Apple Calendar. Native tracker for iPhone & Apple Watch with a private on-device AI Coach. Unlimited workouts free, no account.
```

---

## German (de-DE)

Primary (recommended):
```
Nativer Workout-Tracker für iPhone & Apple Watch. Privater KI-Coach auf dem Gerät, smarte Progression, Supersätze – unbegrenzt tracken, ohne Konto.
```

Alternatives:
```
Trainiere smarter mit privatem KI-Coach, automatischer Progression und vollständigem Apple-Watch-Tracking. Ohne Konto, unbegrenzt viele Workouts kostenlos.
```

```
Deine Routinen, Supersätze und Pausentimer – mit privatem KI-Coach auf dem Gerät und Apple Watch, die jeden Satz trackt. Unbegrenzt tracken, kostenlos.
```

Kalender-Variante – **live seit v1.1.14**, kann verwendet werden:
```
Dein Trainingsplan direkt im Apple-Kalender. Nativer Tracker für iPhone & Apple Watch mit privatem KI-Coach. Unbegrenzt tracken, kostenlos, ohne Konto.
```

---

**The two calendar variants are live-ready as of v1.1.14** (on the App Store 2026-09-04; hold resolved
in the v1.1.17 release pass). They were held because this field is edited without a build: pasting
one before the binary shipped would have promoted a feature the installed app did not have.

**Why they are worth holding for.** No competitor writes planned workouts to the system calendar
(researched 2026-09-03: Strong, Hevy, Fitbod, Jefit, Boostcamp and Alpha Progression all stop at an
in-app history view), so this is the app's only rival-free capability that needs no Apple
Intelligence hardware — and unlike the description, this field can carry it the day it ships without
a submission. Reasoning for keeping it free: `docs/calendar-sync.md` §14.

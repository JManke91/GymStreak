# GymStreak Landing Page — implementation brief & ticket set

**Audience:** the agent(s) implementing the landing page in the **separate repository**
`git@github.com:JManke91/gymstreak-landing.git`. That agent has **no access to the app repo**, so
this file is deliberately self-contained: every fact, every string and every constraint it needs is
inlined below rather than referenced.

**Source:** `docs/acquisition-strategy.md` §4 lever 4 ("Landing page + custom domain", P1). Written
2026-09-06 against app version **1.1.16**.

**Deviations from the acquisition doc, decided by the product owner (these override §4):**
- **No Vercel.** Hosting is **GitHub Pages**. The repo already exists (above); it is empty.
- **The domain is not purchased yet.** Build for the GitHub Pages project URL first
  (`https://jmanke91.github.io/gymstreak-landing/`); DNS + custom domain is a later ticket.

---

## 0. How to use this document

1. Read §1–§9 in full before writing any code. §4 is the feature truth — do not invent capabilities.
2. **Before starting ticket 03 (or any ticket that renders a screenshot), stop and ask the product
   owner for the concrete path to the app screenshots inside the landing-page repo.** They will be
   provided separately. Do not guess a path, do not scaffold placeholder images and move on — ask,
   then map each screenshot to the feature it proves using the mapping table in §5.
3. Tickets are in §10, in dependency order with their blocking edges stated.

### The one-ticket rule (binding)

**Implement exactly one ticket per instruction, then stop and report.**

When the product owner says "implement the next open ticket", "continue", "start ticket 07" or
anything similar, that authorises **one** ticket — the single next unblocked one — and nothing else.
When it is done: report what changed, state which ticket is next, and **end the turn**. Do not begin
the next ticket, do not "quickly also do" an adjacent one because it is small or because it shares a
file, and do not batch several tickets that happen to share a blocking edge (04-09 all block on 04;
that makes them parallel-*eligible*, **not** a batch to do in one go).

The only thing that authorises more than one ticket in a turn is the owner naming them explicitly or
giving a count ("do 04 and 05", "do the next three").

Rationale: every ticket produces output the owner wants to eyeball — copy, layout, a claim about the
app — before the next one builds on top of it. A batch that is 80% right costs more to unpick than a
single ticket that is wrong.

**Stop and ask rather than proceed** whenever a ticket runs into one of the §11 open questions, needs
an asset that is not in the repo, or would require inventing a product claim not present in §4.

---

## 1. What the page is for (and what it is not for)

**It is infrastructure, not a channel.** SEO on a fresh domain takes 6–12 months, so the page is
**not** justified by search traffic. Its immediate job: Reddit posts, YouTube descriptions,
review-site outreach, press mail and the App Store Connect `Marketing URL` / `Support URL` fields
all need somewhere to point, and none of them can happen until this exists.

**The single success metric:** *Web-Referrer* in App Store Connect → Acquisition → Sources going
**non-zero**. It has read zero for ninety days.

**The commercial reality that shapes the design:** the app is at ~13 App Store impressions/day. The
store listing already converts well (20% page-view → download). The problem is reach. Every visitor
this page gets is expensive and hand-delivered — so **the page's only real job is to convert a
visitor into an App Store tap.** Optimize ruthlessly for that. It is a conversion page, not a brochure.

**Non-goals for v1:** no blog engine, no newsletter, no analytics vendor requiring a cookie banner,
no CMS, no backend, no forms that POST anywhere.

---

## 2. Brand & visual direction

The app's design system is called **Onyx**. The landing page must look like the same product.

| Token | Value | Notes |
|---|---|---|
| Background | `#000000` | Pure OLED black. The app is dark-only. |
| Card | `#1C1C1E` | |
| Card elevated | `#262628` | |
| Input / inset | `#2C2C2E` | |
| **Accent / tint** | **`#00FF85`** | Vibrant green. The signature colour. |
| Success | `#30D158` | |
| Destructive | `#FF453A` | |
| Warning | `#FF9F0A` | |
| Info | `#5E5CE6` | |
| PR / record gold | `#FFCC00` | Personal-record badges |
| Text primary | `#FFFFFF` | |
| Text secondary | `rgba(255,255,255,0.6)` | |
| Text tertiary | `rgba(255,255,255,0.4)` | |
| Border | `rgba(255,255,255,0.2)` | |
| Divider | `rgba(255,255,255,0.15)` | |

**Hard contrast rule, inherited from the app:** **never put white text on `#00FF85`.** Text and icons
on the accent are **black** (`#000000`). This applies to CTA buttons, badges, pills — anything with a
green fill. Getting this wrong is the single most visible way to look "not like the app".

**Type:** the app uses SF Pro Rounded (`Font.system(design: .rounded)`) for display/titles and SF Pro
for body. On the web use `-apple-system, BlinkMacSystemFont, "SF Pro Rounded", "SF Pro Display",
system-ui, sans-serif` for headings and the plain system stack for body. **Do not load a webfont** —
the audience is overwhelmingly on Apple devices where the real thing is already installed, and a
webfont costs render-blocking bytes for a page whose whole point is speed. If a fallback is wanted
for non-Apple visitors, self-host **Inter** (variable, subset latin) and never hit Google Fonts.

**Geometry:** corner radii 8 / 12 / 16 / 20 px (the app's `cornerRadiusSM…XL`); spacing scale
4 / 8 / 12 / 16 / 24 / 32. Cards are `#1C1C1E` on `#000`, 1px `rgba(255,255,255,0.08)` hairline, no
heavy drop shadows — depth comes from surface lightness, not shadow.

**Motion:** restrained. Subtle fade/slide-up on scroll-in (`prefers-reduced-motion: reduce` must
disable it entirely). No parallax, no autoplaying video with sound, no scroll-jacking.

**Tone of voice:** matches the app's AI Coach constraints — factual, direct second person, no hype,
**no exclamation marks, no emoji**. Concrete numbers over adjectives. The app's own copy is the
reference; see §6.

**Logo / icon:** the app icon PNG will be supplied with the screenshots (`gym-icon-primary.png`). Use
it for the favicon set, the header mark and the OG image. There is no separate wordmark — set the
product name in SF Pro Rounded Bold.

---

## 3. Product facts (get these right)

| Fact | Value |
|---|---|
| App name | **GymStreak** (one word, capital S) |
| Apple App Store ID | **6756426105** |
| App Store URL — **English pages** | `https://apps.apple.com/app/id6756426105` (storefront-neutral) |
| App Store URL — **German pages** | `https://apps.apple.com/de/app/gymstreak/id6756426105` |
| Platforms | iPhone (iOS 26.1+) and **Apple Watch** (standalone app). **No iPad-specific, no Mac, no Android, no web app.** |
| App UI languages | **English and German only** |
| Current version | 1.1.16 |
| Account required | **No. There is no account and no sign-up, ever.** |
| Backend | **None.** Data lives on-device (SwiftData) and syncs through the user's **own private iCloud** (CloudKit private database). The developer never sees training data. |
| Support email | `julian.manke@googlemail.com` |
| Developer | Julian Manke (sole developer, based in Germany) |

**Locale note on the App Store URL — decided by the owner, do not deviate.** The `/de/` path
segment forces the German storefront, which sends a US or GB visitor to a store page they cannot buy
from. So:

- **English pages link to `https://apps.apple.com/app/id6756426105`** — no locale segment. Apple
  redirects the visitor to their own storefront, in their own language and currency. 28% of users
  are US and 3% GB; they must land somewhere they can actually install from.
- **German pages link to `https://apps.apple.com/de/app/gymstreak/id6756426105`** — the DE
  storefront is 62% of the user base and the German page's visitor is overwhelmingly on it.

The App Store badge component (§7.1) picks the base URL from the page locale, so this is one branch
in one helper and never a decision made at a call site. See §7.5 for how the campaign parameter is
appended to both.

### Pricing (state it accurately or not at all)

- **Free tier is genuinely generous and unlimited for tracking:** unlimited workouts, unlimited sets,
  the full Apple Watch app, supersets, rest timers, Live Activity, Apple Calendar sync, Apple Health
  sync, iCloud sync. **Nothing already created is ever taken away.**
- **GymStreak Pro adds:** unlimited routines (**3 are free**), full analytics (estimated 1RM, training
  volume, 1-year and all-time chart ranges), fixed weekday scheduling, and unlimited AI Coach chat /
  recaps / deep-dives (free gets 5 chat messages, 1 period recap and 1 exercise deep-dive **per
  calendar month**).
- **Price: $4.99 / 4,99 € per month or $24.99 / 24,99 € per year, with a 7-day free trial on the
  yearly plan.** Auto-renews unless cancelled ≥24h before the period ends.
- **There is no lifetime purchase.** Do not mention one.

---

## 4. Feature inventory — the truth about what the app does

Everything below is verified against the shipping code. **Claim nothing that is not in this list.**

### 4.1 Routines & the exercise library
- Reusable **routines**: an ordered list of exercise slots, each with its own planned sets.
- Every set is configured individually: **reps, weight, rest time**.
- Built-in starter library of **96 common gym exercises** (barbell/dumbbell/machine/cable/bodyweight
  staples), seeded locally — no network, works on first launch offline. Users can add, edit and
  delete their own exercises; seeded ones behave identically.
- Exercises are tagged across **20 muscle groups**: Biceps, Triceps, Forearms, Chest, Upper Chest,
  Upper Back, Lats, Lower Back, Shoulders, Front Delts, Side Delts, Rear Delts, Abs, Obliques,
  Quadriceps, Hamstrings, Glutes, Calves, Hip Flexors, plus a General tag.
- **kg / lb** unit preference, applied everywhere including the watch, charts and the AI coach.

### 4.2 Supersets
- Group 2+ exercises so sets interleave: A1 → B1 → A2 → B2 → A3 → B3.
- The app **detects rounds automatically** and only starts the rest timer once every exercise in the
  round is done.
- Fully supported **on both iPhone and Apple Watch**, with bidirectional sync.

### 4.3 Alternative exercises ("the machine is busy" case)
- Any routine exercise can carry **any number of alternatives**, each with its **own set scheme**.
- Mid-workout you can **swap** to an alternative (or back) as long as no set has been completed.
- History records the exercise **actually performed**, not the one planned.

### 4.4 Progressive overload (Double Progression)
- Set a **rep range goal** per exercise, e.g. 8–12.
- Per-set badges show how close each set is to the top of the range.
- When **every set** reaches the top of the range, the app raises a prompt suggesting a weight
  increase; one tap opens an increment picker (1.25 / 2.5 / 5 kg) and applies it — new weight, reps
  reset to the bottom of the range.
- This is the textbook **Double Progression** model, automated.

### 4.5 The live workout
- Start straight from a routine; track every set in real time.
- **Automatic rest timer** between sets, with a compact bar (progress ring, remaining time, **+30s**,
  **Continue**) that expands to a full circular countdown.
- Adjust reps and weight inline mid-workout.
- Add, remove or swap exercises mid-workout.
- A **local notification** brings the user back for the next set when the app is backgrounded.
- Post-workout summary: duration, completed/total sets with percentage, estimated calories, and a
  **per-exercise volume delta vs. the previous session of the same routine** (green ▲ / orange ▼ /
  "New" badge).
- **Template intent:** accepted weight increases and mid-workout edits can be pushed back into the
  routine template, so the plan keeps up with the lifter.

### 4.6 Live Activity & Dynamic Island
- The **rest timer runs on the Lock Screen and in the Dynamic Island** (ActivityKit), showing the
  exercise name and remaining time.
- ⚠️ **Do not claim Home Screen widgets.** The widget extension ships a Live Activity only; the
  other widget targets are unmodified Xcode template stubs. Saying "widgets" would be false.

### 4.7 Apple Watch — fully standalone (the strongest differentiator)
This is the app's most defensible claim: **the complete watch app is free**, where the main
competitor paywalls theirs. Give it real estate.
- Trains **completely independently of the iPhone** — routines sync automatically to the wrist.
- Pre-workout routine overview: exercise count, total sets, and per-exercise planned sets rendered
  as `3 × 8–12 @ 60–80 kg`.
- **Real-time heart rate and calories** via `HKWorkoutSession` + `HKLiveWorkoutBuilder`.
- **Apple Watch Ultra Action Button** completes the current set and advances (Ultra 1/2/3). On
  Series 9/10 and Ultra 2/3, the **Double Tap** gesture does the same.
- **Auto-finish:** completing the last remaining set anywhere in the routine ends the workout,
  closes the HealthKit session and sends it to the iPhone — no navigating back to press Finish.
- Supersets work on the watch too.
- **Crash-safe recovery:** if the watch app is terminated mid-workout, the active workout is
  restored, and completed workouts sit in a durable outgoing queue until the iPhone acknowledges
  them. A finished workout is never lost.

### 4.8 History & analysis
- **Verlauf / History** tab: a "this week" hero with the weekly goal, month-grouped workout cards,
  and a **calendar view** with completed (✓) and upcoming (dashed) day markers.
- Workout detail: header, four stat tiles, per-exercise blocks with **per-set deltas** vs. the
  previous session and **personal-record badges** (gold).
- **Muscle map:** two schematic bodies (front / back) with the muscles that workout trained lit in
  the accent colour — solid for primary movers, 42% tint for supporting ones. **It is interactive:**
  tap a muscle (or its pill) to isolate it and see its set count. The same map appears on a routine
  to show what it *plans* to train. **The most visually distinctive thing in the app — put it on the
  page.** iPhone only.
- Past workouts can be **edited** and **deleted**.

### 4.9 Progress charts
- Per-exercise charts over three metrics: **max weight**, **estimated 1RM**, **training volume
  (weight × reps)**.
- Time ranges: week, month, 3 months, 1 year, all time.
- Free tier: **max weight** metric, up to the **3-month** range. Estimated 1RM, volume, and the
  1-year / all-time ranges are Pro. **No data is ever deleted — the gate is fully reversible.**
- A recent-sets list accompanies each chart.

### 4.10 AI Coach — on device, private
- Uses Apple's **Foundation Models** framework: **entirely on-device, nothing is ever sent anywhere.**
- Five surfaces:
  1. **Post-workout recap** — 2–3 sentences right after saving a workout.
  2. **Period recap** — a multi-section review over any of six ranges (this week → this year).
  3. **Exercise deep-dive** — a 3–4 paragraph analysis of one exercise's progression.
  4. **Workout analysis** — a comparison of a past workout against the previous session of the same
     routine.
  5. **Coach chat** — a multi-turn conversation grounded in the user's own history, with tools for
     next workout, exercise PRs and workout history.
- Voice: factual, exact numbers, no hype, no medical or nutritional advice.
- ⚠️ **Requirement to state honestly: AI Coach needs Apple Intelligence** (iOS 26+ on supported
  hardware, roughly iPhone 15 Pro and newer). The rest of the app works fully without it. **The page
  must say this** — a user who buys expecting AI on an iPhone 13 leaves a one-star review, and the
  App Store rating outranks revenue in this project's guardrails.

### 4.11 Planning & Apple Calendar sync
- Plan each routine either by **rolling cadence** ("every N days", rolling from the last workout) or
  on **fixed weekdays** (Mon/Wed/Fri). Weekday scheduling is Pro; cadence is free.
- The **weekly goal is derived from the plan** — it counts planned sessions that actually fall in the
  current Mon–Sun week, not a hardcoded number.
- **Apple Calendar sync (opt-in, free, no cap):** planned workouts are mirrored into a
  GymStreak-owned calendar as all-day events / a repeating weekday series, and follow the plan as it
  drifts. **No competitor does this** (Strong, Hevy, Fitbod, Jefit, Boostcamp, Alpha Progression all
  stop at an in-app view, researched 2026-09-03). It is a genuine differentiator — feature it.

### 4.12 Apple Health & iCloud
- Every workout syncs to **Apple Health** and counts toward the activity rings; deduplicated so a
  watch workout and its iPhone copy never double-count.
- **iCloud (CloudKit private database)** keeps data current across the user's devices.

### 4.13 Privacy — the second defensible niche
- **No account. No sign-up. No email required. Ever.**
- **No backend, no analytics of training content.** Training data lives on the device and syncs only
  through the user's *own* iCloud account.
- The AI coach runs **on-device**; prompts and training data never leave the phone.
- Full transparency, so the privacy page can say it plainly: the app declares **Purchases → Purchase
  History** in its App Store privacy label (App Functionality and Analytics, not linked to identity,
  not used for tracking) because **RevenueCat** handles subscriptions. That is the only data that
  leaves the device, and it carries no training content. Say this rather than an absolutist "we
  collect nothing" claim — it is both true and more credible.

---

## 5. Screenshots — the protocol

The product owner will place App Store / in-app screenshots inside the landing-page repo.

> **BLOCKING STEP — do this before writing any screenshot markup.**
> Ask the product owner: *"What is the path to the screenshots in the repo, and which file is which
> screen?"* Then map each file to the feature it proves using the table below, and confirm the
> mapping back to them in one short list before building the sections.

Suggested mapping targets (adapt to whatever files actually exist):

| Section | Screenshot that proves it |
|---|---|
| Hero | The routine list or an active workout — the app's most recognisable screen |
| Apple Watch | A watch screen, ideally mid-set or the rest timer (watch screenshots are square-ish and must not be shoehorned into an iPhone frame) |
| Live workout / rest timer | Active workout with the rest bar, or the Live Activity on the Lock Screen |
| Supersets | Routine detail showing the superset connector between two cards |
| Progressive overload | The gold weight-increase prompt |
| Muscle map | Workout detail with both body figures lit |
| History & charts | Verlauf hero / month cards, and an exercise progress chart |
| AI Coach | A recap or the chat |
| Planning / calendar | The planning sheet or the Apple Calendar with mirrored workouts |

**Rendering rules (Apple's, mandatory — see §7.2):**
- Use Apple's official **product bezels** from Apple Design Resources, unmodified. Do not tilt,
  crop, animate, add reflections or fabricate a device frame.
- Show the app as it actually runs — no blank screens, status bar present and complete.
- Serve them responsively: `srcset` + `<picture>`, **AVIF/WebP with a PNG fallback**, explicit
  `width`/`height` to avoid layout shift, `loading="lazy"` on everything below the fold and
  `fetchpriority="high"` on the single hero image.
- Screenshots are the heaviest thing on this page. Budget: **≤ 250 KB per image after conversion**,
  total page weight **< 1.5 MB** on first load.

---

## 6. Copy — the source text

The App Store description below is finished, owner-approved copy in both languages. **Use it as the
factual and tonal source**, but do not paste it verbatim as page copy — a landing page needs shorter,
scannable blocks and its own headlines. Rewrite for the web; never contradict what is here.

### 6.1 English (App Store description, verbatim source)

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
Schedule your routines by cadence or on fixed weekdays. Your weekly goal adapts automatically to your plan. Switch on calendar sync and your training plan appears right in Apple Calendar, alongside everything else in your week.

APPLE HEALTH & ICLOUD
Every workout syncs seamlessly with Apple Health and contributes to your activity rings. With iCloud, your data stays safe and up to date across all your devices.

PRIVACY FIRST
No account, ever. Your training data belongs to you and syncs only through your personal iCloud account — we never see it.

FREE, AND GYMSTREAK PRO
Tracking is free and unlimited: workouts, sets, the Apple Watch app, supersets, rest timers, Apple Calendar sync, Apple Health and iCloud sync. Nothing you have already created is ever taken away.
Pro adds:
– Unlimited routines (3 are free)
– Full analytics: estimated 1RM, volume, 1-year and all-time ranges
– Fixed weekday scheduling
– Unlimited AI Coach chat, recaps and exercise deep-dives

Pro is $4.99/month or $24.99/year, with a 7-day free trial on the yearly plan. It renews automatically unless cancelled at least 24 hours before the period ends; manage or cancel any time in Settings.

Download GymStreak and start your best training today.
```

### 6.2 German (App Store description, verbatim source)

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
Lege für jede Übung einen Wiederholungsbereich fest (z. B. 8–12). Sobald du in allen Sätzen das obere Limit erreichst, schlägt GymStreak automatisch mehr Gewicht vor – nach dem Prinzip der Double Progression.

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
Starte ein Workout aus deiner Routine und tracke jeden Satz in Echtzeit:
– Automatischer Pausentimer zwischen den Sätzen
– Wiederholungen und Gewicht direkt im Workout anpassen
– Übungen hinzufügen, entfernen oder gegen eine Alternative tauschen, wenn die Maschine besetzt ist
– Workout-Zusammenfassung mit Dauer, Volumen und Kalorien

LIVE ACTIVITIES & DYNAMIC ISLAND
Dein Pausentimer läuft auf dem Sperrbildschirm und in der Dynamic Island. Eine Benachrichtigung holt dich rechtzeitig zum nächsten Satz zurück.

FORTSCHRITT SICHTBAR MACHEN
Verfolge deine Entwicklung mit interaktiven Charts:
– Maximales Gewicht
– Geschätztes 1RM (One-Rep Maximum)
– Trainingsvolumen (Gewicht × Wiederholungen)

VORLAGEN, DIE MIT DIR WACHSEN
Übernimm deine Anpassungen nach jedem Workout in die Routinenvorlage – so spiegelt dein Plan immer deinen aktuellen Stand.

PLANE DEINE WOCHE
Plane deine Routinen nach Rhythmus oder festen Wochentagen – dein Wochenziel passt sich automatisch an. Auf Wunsch erscheint dein Trainingsplan in deinem Apple-Kalender.

APPLE HEALTH & ICLOUD
Jedes Workout wird mit Apple Health synchronisiert und trägt zu deinen Aktivitätsringen bei. Über iCloud sind deine Daten auf allen Geräten sicher und aktuell.

PRIVATSPHÄRE AN ERSTER STELLE
Kein Konto, niemals. Deine Trainingsdaten gehören dir und werden nur über dein persönliches iCloud-Konto synchronisiert – wir sehen sie nie.

KOSTENLOS UND GYMSTREAK PRO
Tracken ist kostenlos und unbegrenzt: Workouts, Sätze, Apple-Watch-App, Supersätze, Pausentimer, Kalender-, Apple-Health- und iCloud-Sync. Was du angelegt hast, wird dir nie weggenommen.
Pro ergänzt:
– Unbegrenzt viele Routinen (3 sind kostenlos)
– Alle Auswertungen: 1RM, Volumen, Zeiträume 1 Jahr und gesamt
– Feste Wochentag-Planung
– Unbegrenzten KI-Coach-Chat, Rückblicke und Tiefenanalysen

Pro kostet 4,99 €/Monat oder 24,99 €/Jahr, im Jahresabo mit 7 Tagen kostenlos. Das Abo verlängert sich automatisch, sofern nicht mindestens 24 Stunden vor Ende der Periode gekündigt wird; jederzeit in den Einstellungen kündbar.

Lade GymStreak herunter und starte noch heute dein bestes Training.
```

### 6.3 Claims that are forbidden

- ❌ "No subscription" / "ohne Abo" — **false since the Pro launch.** The no-*account* promise is
  still true and should be used; the no-*subscription* one must never appear.
- ❌ Home Screen widgets (§4.6).
- ❌ A lifetime purchase (does not exist).
- ❌ iPad-optimised, Mac, Android or web versions.
- ❌ AI Coach without stating the Apple Intelligence requirement.
- ❌ "Apple App Store", "iTunes App Store", "at the App Store" — Apple forbids all three. Say
  "on the App Store" / "available on the App Store".
- ❌ Any user testimonial, rating figure, download count or press quote that has not been supplied
  by the product owner. **Invent nothing.** The app currently has very few ratings, so do not build
  a section that needs social proof to look finished.

---

## 7. App Store linking, badges and attribution

### 7.1 The badge (official Apple asset — mandatory)

Apple's App Store Marketing Guidelines govern this and App Review can object to a bad badge.

- **Download the official artwork** from Apple's App Store Marketing Tools:
  `https://toolbox.marketingtools.apple.com/en-us/app-store/us` — or fetch the SVG directly:
  - English: `https://toolbox.marketingtools.apple.com/api/v2/badges/download-on-the-app-store/black/en-us`
  - German: `https://toolbox.marketingtools.apple.com/api/v2/badges/download-on-the-app-store/black/de-de`
  - Also mirrored at `https://developer.apple.com/app-store/marketing/guidelines/images/badge-download-on-the-app-store.svg`
  - Both verified reachable and returning `image/svg+xml` on 2026-09-06.
- **Vendor the SVG into the repo** (`public/badges/`) and serve it locally. Do not hotlink Apple's
  domain from production.
- **Use the black badge with its grey border** (the preferred variant). The white badge only if the
  black one reads visually heavy in a given layout.
- **Minimum on-screen height 40 px.** Clear space around it = **¼ of the badge height** (⅒ in very
  constrained layouts such as a sticky mobile bar). Nothing may intrude into that space.
- **Never modify it:** no recolouring, angling, animating, adding shadows, or rebuilding it as HTML
  text. One badge per layout.
- **"App Store" is always in English, never translated.** The German badge says "Laden im App
  Store" — that is Apple's own localisation; do not hand-make one.
- Serve the localised badge that matches the page locale (en → en-us, de → de-de).

### 7.2 Device frames

- Use Apple's official product bezels from **Apple Design Resources**
  (`https://developer.apple.com/design/resources/#product-bezels`), latest-generation devices only,
  unmodified. No tilting, cropping, animating, reflections, or 3D renders.
- Screens must show the app as it really runs, with a complete status bar and no blank screens.

### 7.3 Wording rules (Apple trademark guidelines)

- Correct: "GymStreak for iPhone", "GymStreak for Apple Watch", "available on the App Store".
- Wrong: "iPhone app GymStreak", "Apple App Store", "at the App Store", "downloadable".
- Product names: **iPhone, iPad, Apple Watch, App Store** — correct capitalisation, singular,
  never all-caps, never translated.
- **Footer credit line required:** *"Apple, the Apple logo, iPhone, Apple Watch and App Store are
  trademarks of Apple Inc., registered in the U.S. and other countries. App Store is a service mark
  of Apple Inc."*

### 7.4 Smart App Banner

Put this in `<head>` on **every** page so a mobile Safari visitor gets a native install affordance:

```html
<meta name="apple-itunes-app" content="app-id=6756426105">
```

### 7.5 Campaign attribution — the point of the whole exercise

**Every** App Store link must carry a campaign parameter, otherwise Web-Referrer in App Store
Connect stays useless and no off-store effort can be measured. Apple's App Analytics campaign
parameters are `pt` (provider token, optional), `ct` (campaign text, ≤40 chars, what shows in App
Analytics) and `mt=8`.

Pattern, per locale (§3):

```
en:  https://apps.apple.com/app/id6756426105?ct=<campaign>&mt=8
de:  https://apps.apple.com/de/app/gymstreak/id6756426105?ct=<campaign>&mt=8
```

Ship a **single helper** (an Astro component or a small TS function) that takes `campaign` and
`locale` and returns the finished URL, so no raw App Store URL is ever hardcoded twice and the
locale branch exists in exactly one place. Suggested `ct` values:

| Placement | `ct` |
|---|---|
| Hero CTA | `web-hero` |
| Sticky mobile bar | `web-sticky` |
| Footer CTA | `web-footer` |
| Apple Watch section | `web-watch` |
| Pricing section | `web-pricing` |
| Support page | `web-support` |
| Privacy page | `web-privacy` |

Add `?ct=…` variants for any future off-site channel (`reddit-applewatch`, `yt-desc`, …) through the
same helper.

---

## 8. Technical decisions

### 8.1 Stack — Astro + Tailwind CSS, static output

**Recommended: Astro 5 with `output: 'static'`, styled with Tailwind CSS v4.**

Why Astro over Next.js here: this is a content page with almost no interactivity, and Astro ships
**zero JavaScript by default** — the two or three interactive bits (mobile nav, FAQ accordion) can be
plain `<details>`/a few lines of vanilla JS. Next.js static export drags a React runtime onto a page
whose entire job is to load instantly on a phone in a gym. Astro also has first-class built-in image
optimisation, which matters because screenshots dominate the payload.

If the implementing agent has a strong reason to prefer Next.js static export, that is acceptable —
but the constraints below (no server runtime, no `next/image` loader that needs a server, base-path
handling, GitHub Actions deploy) are non-negotiable either way.

**No server runtime of any kind.** GitHub Pages serves static files only: no API routes, no
middleware, no SSR, no ISR, no redirects config. Every route must exist as a real HTML file.

### 8.2 Hosting — GitHub Pages

- Repo: `git@github.com:JManke91/gymstreak-landing.git` (exists, empty).
- Deploy with **GitHub Actions** (`actions/configure-pages`, `actions/upload-pages-artifact`,
  `actions/deploy-pages`) on push to `main`, with Pages source set to **"GitHub Actions"** — not the
  legacy `gh-pages` branch.
- Add an empty **`.nojekyll`** file to the published output so Jekyll does not eat directories
  starting with `_` (Astro emits `_astro/`). **This is the single most common way a GitHub Pages
  Astro deploy silently ships without CSS.**

### 8.3 The base-path trap — read this before writing a single link

Until the custom domain exists, the site is served from
**`https://jmanke91.github.io/gymstreak-landing/`** — a **sub-path**, not the root. Every
root-absolute asset URL (`/logo.png`, `/_astro/…`) will 404. When the domain arrives, the site moves
to the root and any hardcoded `/gymstreak-landing/` prefix breaks instead.

**Solve it once:**

```js
// astro.config.mjs
export default defineConfig({
  site: process.env.SITE_URL ?? 'https://jmanke91.github.io',
  base: process.env.BASE_PATH ?? '/gymstreak-landing',
  output: 'static',
  trailingSlash: 'ignore',
});
```

- Never write a root-absolute URL by hand. Use `import.meta.env.BASE_URL` (or Astro's
  `<Image>` / `astro:assets`, which handle `base` for you) for **every** asset and internal link.
- Add a tiny `href()` helper and use it everywhere, so switching to the apex domain is
  **two environment variables in the workflow file**, not a find-and-replace across the repo.
- Verify the built site by serving `dist/` under a `/gymstreak-landing/` prefix locally before the
  first deploy — a link check that passes at the root proves nothing.

### 8.4 Custom domain (later ticket, do not block on it)

When the domain is purchased:
1. Add a **`CNAME`** file containing the bare hostname to `public/` so it lands in `dist/`.
2. DNS at the registrar:
   - **Apex** (`gymstreak.app`): four `A` records → `185.199.108.153`, `185.199.109.153`,
     `185.199.110.153`, `185.199.111.153`, plus the matching `AAAA` records
     (`2606:50c0:8000::153`, `…8001::153`, `…8002::153`, `…8003::153`). **Verify these against
     GitHub's current published Pages IPs at the time of setup — they do change.**
   - **`www` subdomain:** one `CNAME` → `jmanke91.github.io`.
3. In repo Settings → Pages, set the custom domain and wait for the certificate, then tick
   **Enforce HTTPS**.
4. Flip `SITE_URL` / `BASE_PATH` in the workflow (`BASE_PATH=/`) and redeploy.
5. Update every absolute URL that is genuinely absolute: canonicals, OG tags, sitemap, robots.

### 8.5 Analytics

**No cookie-based analytics, no Google Analytics.** A page whose whole pitch is "no account, we
never see your data" cannot ship a tracking cookie banner without undermining itself. Attribution
comes from the `ct` campaign parameters in §7.5, read in App Store Connect. If the owner later wants
traffic numbers, use a cookieless, EU-hosted option (Plausible / Umami self-hosted) — **as its own
decision, not smuggled into this build.**

### 8.6 Quality bar

- **Lighthouse ≥ 95** on Performance, Accessibility, Best Practices, SEO — mobile profile.
- LCP < 2.0 s on a simulated 4G phone; **zero CLS** (explicit image dimensions everywhere).
- Fully responsive from **320 px** to ultrawide. The page must never scroll horizontally.
- Keyboard-navigable, visible focus rings, semantic landmarks, alt text on every screenshot that
  describes the *feature shown*, not "screenshot".
- Colour contrast ≥ 4.5:1 for body text against `#000` / `#1C1C1E` — check `textTertiary`
  (`rgba(255,255,255,0.4)`) and only use it for genuinely decorative text.
- `prefers-reduced-motion: reduce` disables all scroll animation.
- Works with JavaScript disabled (content is static HTML).

---

## 9. Site map

| Route | Purpose | Priority |
|---|---|---|
| `/` | The conversion page. Hero → the three differentiators (Watch, privacy, on-device AI) → feature sections with screenshots → pricing → FAQ → footer CTA. | P0 |
| `/privacy` | Privacy policy. Required by the App Store listing and by the page's own claims. | P0 |
| `/support` | Support + FAQ. Fills the App Store Connect **Support URL** properly (currently the weakest link between the store and the web). | P0 |
| `/impressum` | **Legally required in Germany** (DDG §5) for a commercially operated site by a German operator. Ask the owner for the exact name/address/contact to publish. | P0 |
| `/changelog` | Release notes, seeded from the app's `CHANGELOG.md` (the owner will supply it). | P1 |
| `/de/…` | German mirror of all of the above. 62% of users are on the DE storefront. | P1 |
| `/apple-watch` | "The Apple Watch gym app that doesn't paywall the watch" — the §2-niche content page that earns links from listicle authors. | P2 |
| `/no-account` | "A workout tracker without an account" — the second niche. | P2 |

**Home page section order (recommended, optimise for the App Store tap):**
1. **Hero** — one-line promise, one screenshot, **App Store badge above the fold**, and the honest
   free-tier line ("Track unlimited workouts free. No account.").
2. **Three-up differentiators** — free standalone Apple Watch app · no account, data in your own
   iCloud · AI coach that runs on your device. These are the only three things competitors do not
   have; lead with them, not with "track your workouts".
3. **Apple Watch** — its own full section with a watch screenshot. Longest section on the page.
4. **The live workout** — rest timer, Live Activity, mid-workout edits, alternatives.
5. **Progressive overload + supersets.**
6. **See your progress** — muscle map (make this the visual centrepiece), history, charts.
7. **AI Coach** — with the Apple Intelligence requirement stated inline, not in a footnote.
8. **Plan your week + Apple Calendar** — the "no competitor does this" line belongs here.
9. **Privacy** — short, plain, links to `/privacy`.
10. **Pricing** — free vs Pro table, exactly as §3.
11. **FAQ** — 6–8 questions (Does it need an account? Does the watch app work alone? Do I need
    Apple Intelligence? Is my data private? What is free? Is there an Android version? Which
    languages?).
12. **Footer** — second App Store badge, support/privacy/impressum links, Apple trademark credit line.

A **sticky bottom App Store bar on mobile** is worth building — it is the highest-leverage element
on the page. Respect the badge clear-space rule inside it.

---

## 10. Tickets

Tracer-bullet vertical slices. Each states what it delivers and what it blocks on. **01 and 02 must
land before anything visual; 03 is blocked on the screenshot conversation in §5.**

---

### Ticket 01 — Repo skeleton, Astro + Tailwind, base-path-safe
**Blocks on:** nothing.

Initialise the Astro 5 project in `gymstreak-landing` with Tailwind CSS v4, TypeScript, `output:
'static'`. Configure `site` / `base` from `SITE_URL` / `BASE_PATH` env vars exactly as §8.3. Add the
`href()` helper and use it in the one placeholder page. Add `public/.nojekyll`. Add
`.editorconfig`, `.gitignore`, `README.md` stating the deploy model and the base-path rule.

**Done when:** `npm run build` produces `dist/` with `.nojekyll` present, and serving `dist/` under a
`/gymstreak-landing/` path prefix locally renders with working CSS and no 404s.

---

### Ticket 02 — GitHub Actions deploy to GitHub Pages
**Blocks on:** 01.

Workflow on push to `main`: checkout → setup-node → `npm ci` → `npm run build` (with
`BASE_PATH=/gymstreak-landing`, `SITE_URL=https://jmanke91.github.io`) →
`actions/upload-pages-artifact` (`dist/`) → `actions/deploy-pages`. Correct `permissions`
(`pages: write`, `id-token: write`) and a `github-pages` environment. Pages source set to
**GitHub Actions** in repo settings.

**Done when:** `https://jmanke91.github.io/gymstreak-landing/` serves the placeholder page with
styles, and a second push redeploys it.

---

### Ticket 03 — Design system, layout shell and the App Store CTA component
**Blocks on:** 01. **Also blocks on the §5 screenshot conversation before any screenshot is placed.**

- Tailwind theme carrying the §2 tokens (colours, radii, spacing, type stack) as CSS variables so a
  later tweak is one file.
- Base layout: `<head>` with title/description/canonical/OG/Twitter tags, the **Smart App Banner
  meta** (§7.4), favicon set from the app icon, `lang` attribute, skip-link, header, footer.
- Footer contains the Apple trademark credit line (§7.3) and links to privacy/support/impressum.
- **`<AppStoreBadge campaign="…" locale="…" />`** component: vendored official SVG (§7.1), correct
  black variant, ≥40 px, enforced clear space, locale-matched badge asset (en → en-us, de → de-de),
  and the href built by the campaign helper from §7.5 — which also picks the **storefront-neutral
  URL for `en` and the `/de/` URL for `de`** (§3). **No raw App Store URL anywhere else in the
  codebase.**
- Reusable `Section`, `FeatureBlock` and `DeviceShot` components; `DeviceShot` wraps Apple's
  official bezel and takes `srcset`/AVIF/WebP + dimensions.

**Done when:** the shell renders at all breakpoints from 320 px, the badge passes the size and
clear-space rules, and every App Store link in the built HTML carries a `ct` parameter.

---

### Ticket 04 — Home page: hero + three-up differentiators
**Blocks on:** 03, and the screenshot mapping being confirmed.

Sections 1–2 of §9. Hero with the promise line, the free-tier honesty line, the App Store badge
above the fold, and the hero screenshot with `fetchpriority="high"`. Three-up: standalone Apple
Watch · no account / own iCloud · on-device AI.

**Done when:** LCP element is the hero image, CLS is 0, and the section reads correctly at 320 px.

---

### Ticket 05 — Home page: Apple Watch section
**Blocks on:** 04.

The longest feature section, per §4.7. Watch screenshot in an Apple watch bezel. Must state, in the
user's words: trains without the iPhone, routines sync automatically, live heart rate and calories,
Action Button / Double Tap set completion, auto-finish on the last set, workouts never lost. **State
plainly that the whole watch app is free** — that is the differentiator, not a footnote.

---

### Ticket 06 — Home page: live workout, supersets, progressive overload, alternatives
**Blocks on:** 04.

§4.2–§4.6. Rest timer + Live Activity / Dynamic Island (do **not** say widgets), mid-workout
editing, alternative exercises, superset round detection, the Double Progression prompt.

---

### Ticket 07 — Home page: progress — muscle map, history, charts
**Blocks on:** 04.

§4.8–§4.9. Make the **muscle map** the visual centrepiece of this section. State the chart metrics
and ranges accurately, and that the free tier charts max weight up to 3 months while 1RM, volume and
longer ranges are Pro — framed as what Pro adds, never as something taken away.

---

### Ticket 08 — Home page: AI Coach, planning + Apple Calendar, privacy
**Blocks on:** 04.

§4.10–§4.13. **The Apple Intelligence requirement must appear in the AI section body, not a
footnote.** The calendar section carries the "no competitor does this" claim. The privacy block is
short, plain, and links to `/privacy`.

---

### Ticket 09 — Pricing, FAQ, footer CTA and the sticky mobile App Store bar
**Blocks on:** 04.

Free-vs-Pro comparison exactly as §3 (including the "nothing you already created is taken away"
line, the exact caps, the price and the 7-day yearly trial). FAQ as §9 item 11, as `<details>` so it
needs no JS. Footer CTA badge. Sticky bottom bar on mobile with `campaign="web-sticky"`, respecting
badge clear space and never covering focus targets.

---

### Ticket 10 — `/privacy`, `/support`, `/impressum`
**Blocks on:** 03.

- **Privacy policy** written from §4.13: no account, no backend, data on device + the user's own
  iCloud private database, on-device AI, HealthKit data read/written only locally and to Apple
  Health, and the honest RevenueCat purchase-history disclosure. Include the App Store privacy-label
  wording so the page and the store agree.
- **Support/FAQ** page with the support email `julian.manke@googlemail.com` (obfuscate against
  scraping, but keep it a working `mailto:`), a "how to report a bug" section, and the FAQ reused
  from ticket 09.
- **Impressum** — legally required (DDG §5). The details are confirmed by the owner:

  ```
  Julian Manke
  Tengstr. 36
  80796 München
  Deutschland

  E-Mail: julian.manke@googlemail.com
  ```

  Publish them under `Angaben gemäß § 5 DDG` with a `Kontakt` block beneath, plus a
  `Verantwortlich für den Inhalt nach § 18 Abs. 2 MStV` line naming the same person and address.
  Do **not** add a VAT ID, commercial-register entry or supervisory authority — none apply here, and
  inventing one is worse than omitting it. Keep the Impressum **in German on every locale** (that is
  the convention and what the law expects) and link it from the footer of both the English and the
  German pages. An **EU ODR** line is not required, because nothing is sold from the site — all
  purchases happen on the App Store.

**Done when:** all three pages are linked from the footer and reachable, and the Impressum renders
the block above verbatim.

---

### Ticket 11 — German locale (`/de/…`)
**Blocks on:** 04–10.

Mirror every P0 route under `/de/`. Use §6.2 as the source of truth for German phrasing — it is
owner-approved and uses the app's actual German terminology (Routinen, Sätze, Supersätze,
Pausentimer, Wochenziel, Verlauf, Fortschritt). Serve the **de-de** App Store badge on German pages.
Add `hreflang` alternates both ways and a `x-default`. **No auto-redirect by browser language** —
offer a visible language switch instead; forced redirects break shared links and Apple's crawler.

---

### Ticket 12 — SEO, sitemap, robots, OG images, 404
**Blocks on:** 04–11.

`@astrojs/sitemap`, `robots.txt`, per-page canonical + OG/Twitter cards (generate a static OG image
per page from the app icon and the brand colours — 1200×630), JSON-LD `SoftwareApplication` with the
correct name, operating system (`iOS, watchOS`), offer price and the App Store URL, and a branded
`404.html` (GitHub Pages serves `404.html` automatically). Verify every internal link resolves under
the base path.

---

### Ticket 13 — `/changelog`
**Blocks on:** 03. Also blocks on the owner supplying `CHANGELOG.md`.

Render release notes from a Markdown file committed into the repo (`src/content/changelog.md` or a
content collection). Keep it a manual copy step for now — **do not build a cross-repo automation**;
the app repo is private and this page is not worth a sync pipeline yet.

---

### Ticket 14 — Custom domain cut-over
**Blocks on:** 12, and the domain actually being purchased. **Do not start before the owner says the
domain exists.**

Execute §8.4 end to end: `CNAME` file, DNS records (re-verify GitHub's current Pages IPs), custom
domain in repo settings, Enforce HTTPS, `BASE_PATH=/` and `SITE_URL=https://<domain>` in the
workflow, then a full re-crawl of internal links, canonicals, OG URLs and the sitemap.

**Then hand back to the app repo owner:** the domain must be entered into App Store Connect as both
the **Marketing URL** and the **Support URL**, and `docs/acquisition-strategy.md` §3 row 4 / §4
lever 4 must be updated to shipped in the app repo.

---

### Ticket 15 (P2, optional) — Niche content pages
**Blocks on:** 12.

`/apple-watch` and `/no-account` per §9. These are the pages that give listicle authors and Reddit
threads something specific to link to. Write them as honest comparisons, not marketing — the
audience is people who already know Strong and Hevy.

---

## 11. Open questions for the product owner

The implementing agent should ask these rather than assume:

1. **Screenshot path and file→screen mapping** (blocking, see §5).
2. **The chosen domain name**, once purchased (blocking for ticket 14).
3. Whether the app icon may be used as the site favicon and OG image (assumed yes).
4. Whether a `CHANGELOG.md` copy should ship in v1, or ticket 13 is deferred.

**Already answered — do not re-ask:**

- **Impressum details** — supplied, see ticket 10.
- **App Store link locale** — storefront-neutral on English pages, `/de/` on German pages, see §3.

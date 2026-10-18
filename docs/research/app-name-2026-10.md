# App name research: rename or keep "GymStreak"?

**Date:** 2026-10-17. **Status:** research + recommendation; **the decision is the product owner's**
and is recorded in `docs/acquisition-strategy.md` §4.15, not here. This file feeds lever #15.

**Short answer:** rename, and do it now. Today is the cheapest a rename will ever be: the app has
**3 ratings in DE and 0 in the US**, and ratings are tied to the App ID, so they survive a rename
anyway. The brand query "gymstreak" belongs to a competitor whose lead is still growing.
**Recommended name: `Ironwrist`.** Name field: `Ironwrist: Workout Tracker` (en-US) and
`Ironwrist: Trainingstagebuch` (de-DE). **Runner-up: `Roundset`**, if the fighter positioning
becomes the lead identity.

---

## 1. Why the current name fails

Measured 2026-10-17 with the autocomplete and iTunes Search probes (method:
`docs/marketing/app-store-subtitle-keywords.md` §9). The probe script is in this session's scratchpad
and is not committed; it is a thin wrapper around the two `curl` calls documented there.

| Probe | US | DE |
|---|---|---|
| Autocomplete `gymstreak` | "gymstreak: ai personal trainer", "gymstreak ltd", "gymstreak: gym habit tracker", "gymstreak – workout tracker" (last) | "gymstreak: ki fitness trainer", "gymstreak ltd". **This app is not suggested at all** |
| Apps named *GymStreak* | 5. Top: **GymStreak: AI Personal Trainer, 15,910 ratings** | 2. Top: GymStreak: KI Fitness Trainer, 1,023 ratings |
| This app's ratings | **0** | **3** (5.0★) |

The competitor had **5,118** US ratings on 2026-09-07 (`acquisition-strategy.md` §2); it has
**15,910** now. Every word-of-mouth recommendation ("try GymStreak") ends on their page. Word of
mouth is this app's only channel (`monetization-strategy.md` §10).

## 2. What a rename actually costs (corrects §4.15's list)

| Item | Cost | Note |
|---|---|---|
| Ratings history | **None** | Ratings and reviews belong to the App ID (`6756426105`), not the name |
| Bundle ID, CloudKit container, App Group | **None** | Invisible to users; must **not** change |
| In-app strings naming the app | ~7 lines per language in `Localizable.strings`, 1–3 in `InfoPlist.strings`, 4 watch catalog strings, the `CFBundleDisplayName` values | §4.15 said "1,083 localized strings that mention the name". **Wrong:** 1,083 is the size of the whole string table, not the number of strings that mention the name |
| App Store metadata | App Name ×4 localizations; re-derive the subtitle and keyword fields, because the name tokens change (`app-store-subtitle-keywords.md` §2) | About a day, using the existing method |
| Screenshots and paywall copy | Only where the name is printed | Check the screenshot captions and RevenueCat paywall text |
| Privacy policy and support URL pages | Text edit | |
| Name availability | The App Name must be unique on the store | Reserve it by entering it in App Store Connect early |

**Total: about 2–3 days, mostly metadata.** Nothing is lost except the 3 DE ratings' association with
the old name, and those ratings stay on the listing.

## 3. Criteria

1. **Unique brand query.** Someone told the name finds this app first, in US and DE. Non-negotiable,
   because it is the whole reason to rename.
2. **Hear it, type it.** Spelled the way it sounds, in English and German.
3. **Fits the positioning** (`research/positioning-usp-2026-10.md` §6): the identity is lifting plus
   fight conditioning, and the proof any lifter can verify is the Apple Watch log that never loses a
   workout. The name must not exclude plain lifters, who are most of the switchers.
4. **The descriptor carries the keywords, not the brand.** Apple indexes the whole App Name, so
   `Brand: Descriptor` keeps the head term. The brand only has to be unique and memorable.
5. **A reachable domain.** All short coined `.com`s are registered, so `.app` is acceptable.

## 4. Candidates probed

**Real words collide.** Every dictionary word probed already names established apps in both
storefronts, often with 10k–170k ratings: corner, clinch, rounds, bout, spar, camp, grapple,
southpaw, stance, loadout, forge, kilo, grit, eisen, ringside, ironclad, liftlog, ironlog. Liftbook,
Liftwise, Setwise, LiftMate and LiftKeeper are already small workout trackers. All rejected on
criterion 1.

**Clean in both storefronts** (0 apps with the name, empty autocomplete): `ironwrist`, `setkeeper`,
`roundset`, `ironround`, `hardset`, `gripset`, `strikeset`, `liftfight`, `fightlift`, `matiron`.

| Name | Meaning | Positioning fit | Hear→type | Domain | Verdict |
|---|---|---|---|---|---|
| **Ironwrist** | iron (lifting) + wrist (Watch; also fighters' wraps) | Strong for B (the Watch log), neutral-positive for A | Easy in EN and DE | `ironwrist.app` free, `ironwristapp.com` free; `.com` parked since 2005 | **Recommended** |
| **Roundset** | rounds (fight) + sets (lift) | Encodes A exactly; obscure to a plain lifter | "round set": fine | `roundset.app` free | **Runner-up**, only if A wins its validation |
| Ironround | iron + round | A, weaker than Roundset | OK | `.app` free | Weaker Roundset |
| Setkeeper | keeps your sets (never lost) | B only, gentle | Easy | `.app` taken | Out on domain |
| Hardset | tough, generic | Neither | Easy | `.app` free | Says nothing |
| Gripset, Strikeset, Liftfight, Fightlift, Matiron | — | — | Clunky or exclusionary | mixed | Rejected |

**Prefix caveat.** "Iron…" is a crowded gym prefix: Iron Workout, Iron Gym, IronLog. "Round…" is
crowded with fight timers: RoundReady, Roundwork, RoundFlow. The exact names are unique, but spoken
aloud they sit among look-alikes. Ironwrist's second half is distinctive; Roundset's isn't.

**Why Ironwrist over Roundset:** the Watch proof (B) is verified and searchable today, since
"workout tracker apple watch" is a live US query and en-US already buys `apple watch`. The fighter
identity (A) was built without its validation step and has no search demand. A name should bet on
the proven half and stay compatible with the other. Ironwrist does both.

## 5. Name field, per locale

| Locale | Name (≤30) | Indexed tokens | Consequence |
|---|---|---|---|
| en-US | `Ironwrist: Workout Tracker` (26) | ironwrist, workout, tracker | Same head term as today, so the subtitle and keyword field only need `gym` and `streak` handled, and `gym` becomes **buyable** (§2 of the keyword doc excluded it) |
| de-DE | `Ironwrist: Trainingstagebuch` (28) | ironwrist, trainingstagebuch | **The German name gets a descriptor for the first time.** `trainingstagebuch` moves from the keyword field into the highest-weighted field and frees 18 keyword characters |
| en-GB, en-AU | `Ironwrist: Workout Tracker` | as en-US | Re-check the swap rules in keyword doc §6.1 |

**A quick win that does not depend on the rename:** the German name has no descriptor today.
`GymStreak: Trainingstagebuch` (28) would buy the same weight under the current brand. If the rename
is postponed, ship this alone with the next version.

## 6. Still to verify (the product owner's checks, not researchable from here)

- **Trademark:** search EUIPO (eSearch plus) and USPTO for the chosen name in class 9 (software)
  and class 41 (fitness). A web search found no "Ironwrist" brand (2026-10-17), which is not a
  trademark search.
- **App Store name reservation:** entering the name in App Store Connect is the real uniqueness test.
- **Say it to two training partners** and have them type it. This is criterion 2's only real test.

## 7. Sources

- Probes: Apple search autocomplete (`MZSearchHints`, storefronts 143441/143443) and the iTunes Search
  API, 2026-10-17. Domains: Verisign whois (`.com`) and Google Registry RDAP (`.app`).
- Web: no "Ironwrist" or "Roundset" brand found (2026-10-17); the look-alikes named in §4 came from
  the same searches.

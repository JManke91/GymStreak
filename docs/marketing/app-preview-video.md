# App Store App Preview video

Production notes for the 15–30 s App Preview shown next to the screenshots on the
App Store product page. Research verified 2026-10-21 against Apple's primary sources;
the storyboard and production sections are filled in as the work lands.

## 1. Apple's rules (verified 2026-10-21)

Sources: [App preview specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications),
[App previews overview](https://developer.apple.com/app-store/app-previews/),
[Upload app previews and screenshots](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots),
[Review Guidelines 2.3.4](https://developer.apple.com/app-store/review/guidelines/).

| Item | Rule |
|---|---|
| Duration | 15–30 s |
| Count | up to 3 previews per device size and per language |
| iPhone resolution | 886×1920 portrait (1920×886 landscape) for every Dynamic Island / Face ID iPhone; one upload at this size scales down to all smaller modern sizes |
| Orientation | portrait — a preview whose aspect ratio differs from the screenshots is demoted to "A Closer Look" |
| Codec | H.264 in .mov/.m4v/.mp4 (10–12 Mbps, High Profile ≤ 4.0) or ProRes 422 HQ .mov; progressive; **max 30 fps**; HEVC not listed |
| Audio | stereo AAC 256 kbps, 44.1/48 kHz (optional, but one consistent score if used) |
| File size | ≤ 500 MB; processing up to 24 h |
| Poster frame | defaults to the frame at 5 s; set in App Store Connect; cannot be changed after approval without a new version |
| Playback | autoplays **muted** on the product page and in search results; previews appear before the screenshots |
| Localization | managed per language ("App Preview Sets"); a missing locale falls back to the next best language |
| watchOS | **no previews** — the Watch tab takes screenshots only (312×390 … 422×514) |

Content rules (2.3.4 + overview page):

- Only video screen captures of the app itself, captured at native resolution. No mockups, no people, no hands or fingers, no over-the-shoulder shots.
- Narration, music, UI sounds, text overlays, touch hotspots and simple transitions (dissolve, fade) are allowed.
- Disclose in the footage or end frame if a shown feature needs a subscription or login.
- No prices or currencies, no dates or seasonal references, nothing the app cannot do.
- Device frames / bezels are not mentioned anywhere; 2.3.4 reads as screen captures only, so the video stays edge-to-edge.
- Rights to any music are required.

Apple's capture advice is QuickTime from a connected iPhone. Simulator footage at
native resolution is indistinguishable, but the deliverable must still be 886×1920.

## 2. What makes a preview convert (research summary)

Sources: Apple overview page, SplitMetrics, AppFollow, Yellowhead, Gummicube, AppAgent
(vendor numbers are directional, not primary data).

- Previews move conversion by roughly +5 % to +30 % by category; badly made ones go negative. Failure modes: slow or abstract opener, logo intro, text overload, footage that does not match the real app, orientation mismatch, poster frame unrelated to the video, untranslated captions.
- Most viewers watch roughly 7–11 s. The first 3 s decide; the key message never goes at the end.
- Open on the hero action or the outcome (a number going up), never on brand.
- Muted autoplay: one short caption per scene (3–6 words), large and high-contrast, on screen ≥ 2 s. Record clean footage and overlay captions in the edit so EN and DE share one capture.
- 3 features max, 2–3 s per scene, smooth real interactions, quick dissolves only, no loading states, no bezels, portrait.
- Attachment comes from showing the user's own outcome: the set logged, the rest timer running, the PR badge, the chart going up. One accent colour on a minimal UI.
- Two 15 s previews on different features often beat one 30 s video; test with Product Page Optimization (≥ ~1 000 installs per variant).
- The poster frame must stand alone and should match the opening frames.

Shot checklist: first frame = hero action or rising number · first 3 s work silent ·
≤ 3 features · 2–3 s per scene · one caption each · portrait, native, edge-to-edge ·
realistic seeded data · end on the outcome, not the logo · EN + DE captions.

## 3. Feature ranking for the video

Positioning: native tracker for iPhone and Apple Watch, fast, private, account-free.
Aha path (free by rule): build a routine → train it → see it logged → see the number go up.

| # | Feature | Device | Why it films well |
|---|---|---|---|
| 1 | Standalone Apple Watch workout + full-screen rest timer | Watch | the lead differentiator; set completion, HR, draining timer |
| 2 | Muscle map lit after a workout | iPhone | most visually distinctive screen |
| 3 | Active workout + rest timer Live Activity (Lock Screen / Dynamic Island) | both | motion and "it runs while you rest" |
| 4 | Progressive-overload prompt (gold "increase weight") | iPhone | the number going up, literally |
| 5 | Supersets with connector + round detection | both | visible structure |
| 6 | History: PR badges, per-set deltas, calendar | iPhone | the outcome |
| 7 | Progress chart (Max Weight, 1M/3M) | iPhone | the outcome over time |
| 8 | On-device AI Coach | iPhone | innovative, but needs Apple Intelligence and has a monthly taster |
| 9 | Workout share card | iPhone | social proof loop |
| 10 | Fight conditioning / round timer | both | niche differentiator |

Pro-gated, must not be shown as free (docs/monetization-strategy.md §4.2a): more than
3 routines; 1RM and volume chart metrics and the 6M/1Y/all ranges; AI Coach beyond the
monthly taster; fixed-weekday scheduling; conditioning weeks 5–12. Safe chart shot:
**Max Weight at 1M or 3M.** Everything else above is free.

Brand: Onyx design system, accent `#00FF85`, background `#000000`, cards `#1C1C1E`,
PR gold `#FFCC00`, dark-only, SF Pro Rounded Bold display type, black text on green.
Tone: factual, no exclamation marks, no emoji. Logo: `Logo/gym-icon-primary.png`.
Name: "GymStreak" (a rename to "Ironwrist" is under consideration in
docs/acquisition-strategy.md §15 — keep the end card easy to swap).

## 4. Capture pipeline (from the existing screenshot lane)

- Build: `xcodebuild -project GymStreak.xcodeproj -scheme GymStreak -destination 'platform=iOS Simulator,id=<UDID>' -configuration Debug build`, then `xcrun simctl launch <UDID> com.shotat24fps.GymStreak -UI_TESTING 1 -onboarding.flowCompleted YES -AppleLanguages '(en)' -DISABLE_NOTIFICATIONS 1`.
- Scripted flows: a throwaway XCUITest (`build-for-testing` + `test-without-building -only-testing:GymStreakUITests/<Class>`) taps deterministically while `xcrun simctl io <UDID> recordVideo` records. This does not hijack the mouse.
- Known prompts to dismiss: AI Coach opt-in ("Maybe later"), StoreKit "Sign in with Apple Account" (springboard Cancel), notification permission.
- Seeder limits: `-UI_TESTING` seeds 16 exercises, 3 routines and 5 sessions at identical weights over ~9 days, so charts are flat and no PR badges appear. A convincing "number goes up" shot needs a progression seed (8–12 weeks, rising weights).
- Paywall args (`-FOUNDER_SIMULATE_PRECUTOFF`, `-PRO_GATING_OFF`) must stay **off** so the capture only shows free features.
- Watch: `watch_screenshots` lane uses Apple Watch Ultra 3 (49 mm) and Series 11 (46 mm) with `WatchTestDataSeeder` under `-UI_TESTING`; the XCUITest runner on the watch has failed before ("Scene activation failed"); fallback is `simctl install` + launch on a booted watch simulator and simctl-driven taps.
- Existing store assets: six live 1242×2688 screenshots (not reproducible from the repo); never run `fastlane upload_screenshots` (docs/marketing/app-store-connect-actions.md §7.2). No prior preview video exists.

## 5. Open decisions

Filled in once the user has answered: tool, footage source (simulator vs device),
progression seed, feature set, music, name on the end card.

# AI Coach Entry Point — Concept Analysis (Coach Tab vs. Floating Companion)

**Status: Concept B IMPLEMENTED (2026-07-10) — see "Implementation record" at the end.** Triggered by the UX issue that both the AI Coach settings gear and the chat entry lived only in the History tab header (Phase 3 of `docs/ai-coach-chat-plan.md` put them there). Two concepts were fully designed and compared: a conventional 4th "Coach" tab and a floating, always-present companion surface. Research was done via the ios-ux-ui-expert and ios-api-researcher agents against the actual codebase.

## Current state (what this replaces)

- Root: `ContentView.swift` — plain `TabView` with 3 tabs (Routines, Exercises, History), each a `NavigationStack` whose root hides the system nav bar and draws a custom 32pt header.
- Only entry points: gear → `AICoachSettingsView` and sparkle → `CoachChatView`, both solely in `HistoryView`'s header. No general app settings screen exists anywhere.
- Gating today: sparkle shown only when `AICoachAvailability.shared.isAvailable && AICoachPreferences.shared.isChatEffectivelyEnabled` — a never-opted-in user has **no way to discover the chat at all**.
- `ActiveWorkoutView` and `CreateRoutineView` are `fullScreenCover`s (RoutinesView.swift ~lines 60–70); the one-time opt-in (`AICoachOptInView`) is a `fullScreenCover` at the TabView level.
- `CoachChatView` cancels the in-flight stream in `onDisappear`; its view model is created per push.

## Concept A — Dedicated 4th "Coach" tab (recommended to ship first)

- **Tab is always present** in the tab bar (sparkle glyph); never hide/show it based on preference or availability — only its *content* branches. Apple's own apps (Wallet, Fitness) keep tabs present with explanatory states; a tab that appears/disappears breaks spatial memory.
- Content by state (all states exist in `AICoachAvailability` + `AICoachPreferences`):
  - `isChatEffectivelyEnabled` → `CoachChatView` as tab root (unchanged screen).
  - Available, not opted in → in-tab "Turn on AI Coach" invite reopening `AICoachOptInView`. (New state — fixes the zero-discoverability gap.)
  - Ineligible device → unavailable state reusing `ai_coach.settings.unavailable_banner.*` copy.
  - Deliberately off (master or chat toggle) → "turned off — enable in Settings" + direct link; visually distinct from "unavailable" (a choice must not look like a system limitation).
- **Settings gear moves to the Coach tab's header** (same custom-header pattern). No premature general-settings hierarchy: `AICoachSettingsView` is self-contained and slots under a future `SettingsView` as a pure relocation.
- History header: remove gear + sparkle + their `navigationDestination` state (no redundant second entry point).
- Implementation notes: verify tab switching does NOT fire `CoachChatView.onDisappear` (would cancel an in-flight stream); optional one-time `.badge("New")` cleared on first visit.
- Rejected alternatives: sparkle+gear repeated across all 3 headers (crowds headers that already carry primary `+` actions; triplicated gating), chat as sheet (keyboard + accidental swipe-dismiss during streaming), settings inside chat only (not-opted-in users can't reach settings).

## Concept B — Floating companion ("most modern" option)

### UX design (if built)

- **Form factor: persistent mini-bar above the tab bar** (Apple Music mini-player pattern) — NOT a draggable bubble (collides with the AssistiveTouch mental model, hand-rolled snap physics, undermines one-handed reach) and NOT a FAB (Material, not HIG; every screen would need a second hand-maintained bottom inset).
- Visible on all tab roots and pushed detail screens. **Structurally invisible during any `fullScreenCover`** (active workout, create routine, opt-in) — also correct product-wise: mid-set is when a chat invite should not compete for attention. Hides while another view holds keyboard focus. No scroll-auto-hide (the app has zero scroll-hide chrome; don't invent a new pattern).
- **Expand:** tap morphs bar → full chat via `.navigationTransition(.zoom)`; collapse reverses it.
- **Ambient state — honest version:** a static unread-answer dot (from the persisted `ChatConversationStore`). A live "streaming" glow on the collapsed bar would require decoupling generation from view lifecycle (today `onDisappear` cancels the stream) — a real scope addition, not a placement change.
- **Contextual pre-seeding (the genuinely innovative part):** on screens with one clear anchor entity (ExerciseDetail → Exercise, WorkoutDetail → session, RoutineDetail → routine), pre-seed ONE of the chat's existing empty-state suggestion chips with a screen-relevant question ("What's my trend on Bench Press?"). UI-level name pre-fill only — no model reading the screen, no new privacy surface, never auto-sent, single anchor only.
- **Gating is strictly harder than the tab:** must hide entirely when the user turned the feature off (a glowing brand mark ignoring an explicit opt-out is worse than a quiet tab); the not-opted-in invite state must be impression-capped with a cooldown (new state tracking) or it's an app-wide nag; when hidden it explains nothing (zero discoverability for ineligible users).

### Technical mechanisms (ios-api-researcher findings — do not re-research)

- **Buildable today on iOS 18.5, no private API, no second window:** root `ZStack` overlay above the `TabView` persists across tab switches AND pushed `NavigationStack` destinations for free (same window hierarchy). Use `.ignoresSafeArea(.keyboard)` to keep it from drifting with unrelated keyboards; no automatic "above the tab bar" anchor exists — position manually.
- **Overlay does NOT stay above `.sheet`/`.fullScreenCover`** (separate UIKit presentation layers). Workaround exists — second `UIWindow` with high `windowLevel`, transparent `UIHostingController`, custom `hitTest` pass-through ([fivestars.blog/swiftui-windows](https://www.fivestars.blog/articles/swiftui-windows/)) — but it's a genuine UIKit-bridging surface; NOT recommended unless a pill above modals becomes a hard requirement.
- **Expansion transition:** `.matchedTransitionSource(id:in:)` + `.navigationTransition(.zoom(sourceID:in:))` — **iOS 18.0+**, works with `fullScreenCover` (NOT with `.sheet` — silently degrades to full screen, [douglashill.co/zoom-transitions](https://douglashill.co/zoom-transitions/)). Modifier must be on the destination's *root* view. `matchedGeometryEffect` across presentation boundaries is not reliable — don't use it. Delay `@FocusState = true` until the zoom settles so the keyboard doesn't fight the morph.
- **iOS 26 `tabViewBottomAccessory`** ([docs](https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory%28content%3A%29)) is the productized Apple Music mini-player: `@Environment(\.tabViewBottomAccessoryPlacement)` gives `.expanded`/`.inline`, pairs with `.tabBarMinimizeBehavior(.onScrollDown)`. **Hard 26.0+ floor, no back-deploy.** On an 18.5 target, `if #available` would mean maintaining two parallel affordance implementations. Beta-era caveat: placement-detection reported flaky ([createwithswift.com](https://www.createwithswift.com/enhancing-the-tab-bar-with-a-bottom-accessory/)). Claim that the iOS 26 Fitness app uses this API is UNCONFIRMED.
- **Draggable bubble:** no public system component (AssistiveTouch is private/OS-level); pure custom DragGesture + edge-snapping + manual Dynamic Island/home-indicator clamping + ScrollView gesture conflicts. Skip.
- **Lifecycle win if built:** one root-owned `fullScreenCover` + a view model owned above the cover (wired via `AppDependencies`, not `@State` inside the cover content) replaces per-tab pushes and collapses stream cancellation to a single dismiss point.

## Head-to-head

| Axis | Coach tab | Floating mini-bar |
|---|---|---|
| Discoverability | One tap away, always explains itself | Best-in-class when enabled; zero when hidden |
| Intrusiveness | Zero when not selected | Permanent element on every screen; nag risk |
| Screen estate | Already sunk (tab bar) | Permanent vertical cost app-wide |
| Gating states | 4, all self-explanatory in-tab | More states, incl. impression-capped invite; hidden states explain nothing |
| Accessibility | System tab semantics | VO focus-order insertion on every screen; Reduce Motion strips the zoom morph |
| Maintenance | Self-contained | Cross-cutting tax: insets, z-order, keyboard, fullScreenCover-exclusion list on every future screen |
| Modern/innovative factor | Conventional | High (iOS-26-era companion pattern + contextual pre-seeding) |

## Decision recorded

**User input (2026-07-10): the minimum deployment target MAY be raised to iOS 26, and dual implementations are ruled out.** This removes Concept B's main technical objection — with a 26 floor, the floating companion bar is built on the native `tabViewBottomAccessory` (system-managed insets, z-order, accessibility, Music-style collapse), not a hand-rolled overlay. The remaining tradeoffs vs. the Coach tab are purely product-level: harder gating matrix (must hide when disabled; impression-capped opt-in invite) and permanent screen presence, vs. best-in-class discoverability + the contextual pre-seeding angle. The zoom-morph expansion (iOS 18+) works in either concept.

## Implementation record (2026-07-10, same day)

- **`ContentView.swift`**: `.tabViewBottomAccessory(isEnabled: isCoachBarVisible) { CoachBarView }` + `.tabBarMinimizeBehavior(.onScrollDown)` on the TabView; tapping the bar presents `fullScreenCover { NavigationStack { CoachChatView() } }` with `.navigationTransition(.zoom)` morphing from the bar's `.matchedTransitionSource`. The cover's `onDismiss` is the **single stream-cancellation point** (`CoachChatService.shared.cancel()`); `CoachChatView` no longer cancels in `onDisappear`, so pushing settings inside the chat stack doesn't kill a streaming answer.
- **API constraint discovered (keep):** `tabViewBottomAccessory(isEnabled:content:)` is **iOS 26.1+** (the plain `content:`-only variant is 26.0). The app target was bumped 26.0 → 26.1 (user-approved). Widgets/tests targets untouched.
- **`CoachBarView.swift`** (`Presentation/Views/AICoach/Chat/`): accessory content only (system draws the capsule) — sparkle + "Ask your coach" (`ai_coach.chat.bar.title`), reads `@Environment(\.tabViewBottomAccessoryPlacement)` to compact itself when `.inline` (collapsed tab bar).
- **`CoachScreenContext.swift`** (`Presentation/ViewModels/AICoach/`): `@Observable @MainActor` singleton with `anchor: Anchor?` (`case exercise(name:)`). `ExerciseProgressChartView` sets it in `onAppear`/`onChange(of: currentExerciseName)` and clears in `onDisappear`. **Gotcha (caught in review):** presenting a fullScreenCover DOES fire the covered screen's `onDisappear`, in an order not guaranteed relative to the chat's `onAppear` — so the chat never reads the live `anchor`; instead the bar's tap action calls `freezeForPresentation()`, which snapshots it into `presentedAnchor` synchronously before any presentation lifecycle runs, and the view model reads only the frozen copy. `CoachChatViewModel` default-injects it and swaps the generic PR suggestion chip for an anchored one (`ai_coach.chat.suggestion.anchor_pr`). **Deliberate omission:** routine/workout-detail anchors — today's 3 tools ground an anchored *PR* question well, but have no volume-trend/routine-details tools yet (Phase 4); add those anchors when the tools exist.
- **Chat toolbar**: xmark dismiss (leading), gear → `AICoachSettingsView` pushed inside the chat's own NavigationStack (trailing). History header kept its gear (settings only) until 2026-08; its sparkle chat entry from the Phase 3 morning build was removed the same day.
- **Deliberate simplification vs. the spec above:** no impression-capped invite state — the existing one-time `AICoachOptInView` cover remains the only opt-in prompt; the bar is simply hidden until `isChatEffectivelyEnabled`.

**DECISION (2026-07-10): Concept B — floating coach bar.** Rationale: app goals are innovation, convenience, and a "wow" effect for user acquisition; iOS 26 minimum deployment target approved (single codebase, native `tabViewBottomAccessory`). Settings placement: gear stays in the History header (settings only — no longer arbitrary since chat is globally reachable) plus a gear in the expanded chat's toolbar; a general Settings screen is deferred until the app actually needs one. **Superseded 2026-08:** the app did need one — a dedicated Settings tab now owns the AI Coach settings and the History gear was removed (the chat toolbar gear stays). See [Settings Tab](./settings-tab.md). Opt-in simplification vs. the spec above: the existing one-time `AICoachOptInView` fullScreenCover (with its 7-day re-prompt logic) remains the sole opt-in mechanism — the bar simply stays hidden until `isChatEffectivelyEnabled`, which removes the impression-capped-invite machinery entirely (don't over-build). Deferred: unread-answer dot (generation is view-lifecycle-bound today, so an unseen finished answer is a near-impossible state), drag-to-reposition (never), second-UIWindow overlay (never, absent a hard requirement).

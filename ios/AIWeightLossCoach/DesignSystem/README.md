# Design System — install & rules

## Install

Upload all nine `DS*.swift` files to:

```
ios/AIWeightLossCoach/DesignSystem/
```

XcodeGen globs source directories, so no `project.yml` change is needed
unless your config lists files individually.

No new dependencies. Swift Charts and SF Symbols ship with the SDK.

## One conflict to resolve

Your `Core/Theme.swift` defines `Palette`, used as `.tint(Palette.pine)`
in `AIWeightLossCoachApp.swift`.

Leave `Theme.swift` in place for now — nothing here collides with it, so
the app keeps compiling. As screens migrate, replace `Palette.pine` with
`DS.Colors.brand` and delete `Theme.swift` once nothing references it.

Change the app tint now, in `AIWeightLossCoachApp.swift`:

```swift
.tint(DS.Colors.brand)
```

## Wire up appearance and haptics at launch

In `AppDelegate.application(_:didFinishLaunchingWithOptions:)`:

```swift
DS.applyGlobalAppearance()
DS.Haptics.isEnabled = UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true
```

## See it working

Open `DSGallery.swift` in Xcode and run the canvas previews. Three are
included: light, dark, and accessibility-large text. Anything that breaks
in one of those three is a bug in the component, not the screen using it.

During development, put a hidden entry in Settings that pushes
`DSGallery()` so you can check components on a real device.

---

## Rules

These are what make the system hold together as more screens land.

**Never write a literal value in a view.** No `Color.green`, no
`.padding(20)`, no `.font(.system(size: 17))`. If a token is missing, add
it to the token file — don't inline it.

**Compose from components.** A new screen should be assembling `DSCard`,
`DSMetricCard`, `DSCoachCard` and friends. If you find yourself writing a
background + corner radius + shadow stack, the component you need doesn't
exist yet — build it here first.

**Every async screen renders three states.** Loading, empty, error. Use
`DSAsyncContent` or handle `DSLoadState` explicitly. A spinner on its own
is not a loading state.

**Haptics come from the component.** Buttons and chips fire their own.
Don't add a second one at the call site.

**Check dark mode in the same commit.** Every token is dynamic, so it's
free — but only if you look.

---

## Token reference

| Group | Namespace | Example |
|---|---|---|
| Colour | `DS.Colors` | `DS.Colors.brand`, `DS.Colors.textSecondary` |
| Metric identity | `DSMetric` | `DSMetric.protein.color` / `.icon` / `.label` |
| Type | `DS.Typography` | `DS.Typography.title2` |
| Spacing | `DS.Space` | `DS.Space.lg` (16) |
| Radius | `DS.Radius` | `DS.Radius.lg` (20) |
| Elevation | `DS.Shadow` | `.dsShadow(.low)` |
| Motion | `DS.Motion` | `DS.Motion.standard` |
| Haptics | `DS.Haptics` | `DS.Haptics.success()` |
| Sizes | `DS.Size` | `DS.Size.minTapTarget` (44) |

## Component reference

| Component | Use for |
|---|---|
| `DSScreen` | Every screen's outer scaffold |
| `DSTabBar` | Root navigation |
| `DSCard` | All content containers |
| `DSGlassPanel` | Floating/transient overlays only — never content |
| `DSSectionHeader` | Titles with optional trailing action |
| `DSCoachCard` | AI output — the only gradient at this level |
| `DSMetricCard` / `DSStatTile` | Numbers with goal, delta, sparkline |
| `DSProgressRing` / `DSRingCluster` / `DSRingSummary` | Daily goals |
| `DSScoreDial` | 0–100 health score |
| `DSProgressBar` | Compact progress in rows |
| `DSTrendChart` | Time series with scrub |
| `DSForecastChart` | Projection with confidence band |
| `DSBarChart` / `DSSparkline` / `DSMacroBar` | Supporting charts |
| `DSPrimaryButton` / `DSSecondaryButton` / `DSTextButton` / `DSIconButton` | Actions |
| `DSChip` / `DSSegmentedControl` / `DSToggleRow` / `DSListRow` | Selection & settings |
| `DSEmptyState` / `DSErrorState` / `DSBanner` | States |
| `DSSkeletonCard` / `DSShimmerLines` / `.dsShimmer()` | Loading |

---

---

## Liquid Glass rules

Glass is gated behind `#available(iOS 26, *)` and falls back to
`.ultraThinMaterial` on iOS 17–25. Deployment target stays **iOS 17**.

Use `.dsGlass(in:interactive:tint:)` — never call `.glassEffect()`
directly, or the fallback and the Reduce Transparency path are lost.

**Glass is allowed on:** tab bar · floating action buttons · navigation
bars and toolbars · sheet chrome · context menus and transient overlays.

**Glass is not allowed on:** login form · dashboard cards · meal cards ·
chat bubbles · analytics cards · paywall content.

Apple's HIG puts Liquid Glass in the functional layer only. Stacked
glass goes muddy, and glass behind dense text fails contrast. An app
with glass everywhere reads as one that found a new modifier rather than
one that was designed.

Three more rules:

- Apply `.dsGlass` **after** layout and appearance modifiers.
- Wrap sibling glass elements in `DSGlassContainer` so they blend as a
  group rather than as separate panes.
- `tint:` is semantic — a primary action, an active state. Never
  decoration.

**Test with Reduce Transparency on.** It's the most common Liquid Glass
review failure. `.dsGlass` handles it, but only if you look.

---

## Two design decisions worth knowing

**Rings over-fill rather than cap.** Passing 100% draws a brighter second
lap. Overshooting a goal should feel rewarded, not clipped.

**The forecast chart draws a confidence band, not a line.** A single
predicted line implies certainty the model doesn't have — and a user who
believes a precise number and then misses it churns. The band is an
honesty mechanism as much as a visual one.

## Before onboarding

Two things from your spec to settle first, since both bake into onboarding:

- **Metabolic age** isn't a real clinical metric. It's engagement theatre
  and it draws App Store health-claim scrutiny. Consider "metabolic
  profile" with real inputs instead.
- **Calorie targets need a floor and a BMI gate** before they render.
  Auto-generating an aggressive deficit for an underweight user is the one
  failure mode in this category that genuinely harms people. Design the
  guardrail into the generator, not the UI.

---
name: Fitling
description: A character-goods catalog for food and training. Each partner has its own card and ribbon colour, and the numbers stay strict.
colors:
  ink: "#231A33"
  ink-dark: "#F6F2FC"
  ink-soft: "#5E5470"
  ink-soft-dark: "#BDB3CC"
  ground: "#EFE9F8"
  ground-dark: "#1B1524"
  card: "#FFFFFF"
  card-dark: "#2A2234"
  track: "#DCD3EA"
  track-dark: "#3D3349"
  card-shadow: "rgba(35, 26, 51, 0.12)"
  card-shadow-dark: "rgba(0, 0, 0, 0.5)"
  on-ribbon: "#231A33"
  sprout: "#86D45A"
  sprout-tint: "#DCF3DF"
  sprout-tint-dark: "#1F3A26"
  ember: "#FF9442"
  ember-tint: "#FFE4D2"
  ember-tint-dark: "#42281B"
  pip: "#FFD23F"
  pip-tint: "#FFF2C2"
  pip-tint-dark: "#3E3517"
  pebble: "#9AA9C2"
  pebble-tint: "#E2E8F1"
  pebble-tint-dark: "#29313E"
  protein: "#FF7B6B"
  carbs: "#FFC93C"
  fat: "#6EC1F0"
typography:
  display:
    fontFamily: "SF Pro Rounded, ui-rounded, system-ui"
    fontSize: "34px"
    fontWeight: 900
  headline:
    fontFamily: "SF Pro Rounded, ui-rounded, system-ui"
    fontSize: "17px"
    fontWeight: 800
  title:
    fontFamily: "SF Pro Rounded, ui-rounded, system-ui"
    fontSize: "20px"
    fontWeight: 400
  body:
    fontFamily: "SF Pro Rounded, ui-rounded, system-ui"
    fontSize: "17px"
    fontWeight: 400
  label:
    fontFamily: "SF Pro Rounded, ui-rounded, system-ui"
    fontSize: "17px"
    fontWeight: 700
  label-small:
    fontFamily: "SF Pro Rounded, ui-rounded, system-ui"
    fontSize: "15px"
    fontWeight: 700
  numeral-large:
    fontFamily: "SF Pro Rounded, ui-rounded, system-ui"
    fontSize: "34px"
    fontWeight: 900
    fontFeature: "tnum"
  numeral:
    fontFamily: "SF Pro Rounded, ui-rounded, system-ui"
    fontSize: "20px"
    fontWeight: 900
    fontFeature: "tnum"
  caption:
    fontFamily: "SF Pro Rounded, ui-rounded, system-ui"
    fontSize: "13px"
    fontWeight: 400
rounded:
  card: "24px"
  ribbon: "22px"
  capsule: "9999px"
spacing:
  xs: "4px"
  s: "8px"
  m: "12px"
  l: "16px"
  xl: "24px"
  xxl: "32px"
components:
  button-primary:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.card}"
    typography: "{typography.label}"
    rounded: "{rounded.capsule}"
    padding: "0 16px"
    height: "54px"
    width: "100%"
  button-primary-disabled:
    backgroundColor: "{colors.track}"
    textColor: "{colors.ink-soft}"
    rounded: "{rounded.capsule}"
    height: "54px"
  button-secondary:
    backgroundColor: "{colors.card}"
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    rounded: "{rounded.capsule}"
    padding: "0 16px"
    height: "54px"
    width: "100%"
  name-plate:
    textColor: "{colors.on-ribbon}"
    typography: "{typography.headline}"
    rounded: "{rounded.capsule}"
    padding: "4px 12px"
  name-plate-in-card:
    backgroundColor: "{colors.track}"
    textColor: "{colors.ink}"
    typography: "{typography.headline}"
    rounded: "{rounded.capsule}"
    padding: "4px 12px"
  targets-card:
    backgroundColor: "{colors.card}"
    textColor: "{colors.ink}"
    rounded: "{rounded.card}"
    padding: "16px"
  macro-ribbon:
    textColor: "{colors.on-ribbon}"
    rounded: "{rounded.ribbon}"
    padding: "8px 16px"
    height: "44px"
  figure-card:
    textColor: "{colors.ink}"
    typography: "{typography.caption}"
    rounded: "{rounded.card}"
    padding: "12px"
  progress-pill:
    backgroundColor: "{colors.ink}"
    rounded: "{rounded.capsule}"
    height: "8px"
  progress-pill-todo:
    backgroundColor: "{colors.track}"
    rounded: "{rounded.capsule}"
    height: "8px"
---

# Design System: Fitling

Values are iOS points (1 px in the tokens = 1 pt). Type sizes are the Dynamic Type sizes at the default text size; every style scales with the user's setting. Keys ending in `-dark` are the dark appearance of the same asset-catalog colour (`Fitling/Resources/Assets.xcassets`); SwiftUI resolves the pair automatically, so code always names the base colour (`Color.ground`, never a dark variant).

## Overview

**Creative North Star: "The Character Catalog"**

Fitling looks like a collector's catalog of sixteen partners: soft 3D toy animals that grow from a round baby into a muscular champion. Each partner has its own pastel tint, a name plate in its ribbon colour, and one line of character. The rest of the app is built from the same few materials: a soft lilac ground (deep plum in dark mode), white rounded cards, saturated ribbons with dark ink lettering, and heavy rounded type for names and numbers. The tone is warm and toy-like, but the numbers stay strict. Figures are tabular, heavy and in ink, and every calculation sits next to its explanation.

Density is calm. A screen holds one main idea, either a catalog grid, a single targets card, or one list section on the ground. Primary actions sit at the bottom within thumb reach. System navigation, lists, pickers and the Sign in with Apple button are kept and restyled rather than replaced, so the app reads as native iOS in its own colours.

There are no gradients in the interface. The partners are soft 3D renders with their own light and shadow. Navigation bars are opaque and part of the page, never frosted.

**Key Characteristics:**
- Pastel ground, white cards with continuous 24 pt corners, saturated ribbons.
- SF Rounded throughout; Heavy for names and numbers, Bold for actions.
- Ink (never system blue) for tint, text, checkmarks and the primary action.
- Partners are 3D toy figures, stacked from rendered layers, that look the same in light and dark mode.
- Every layout has an accessibility-size variant that stacks instead of squeezing.

## Colors

A muted lilac-and-ink base carries a small set of saturated ribbon colours. Each ribbon colour belongs to one partner species or one macro.

### Primary
- **Plum Ink** (`ink`): text, the primary capsule button, the app tint (checkmarks, links, caret, toolbar buttons, back button) and the done steps of the onboarding progress. In dark mode it becomes near-white lilac (`ink-dark`). `AccentColor` carries the same pair.

### Secondary
- **Species ribbons** (`PartnerRibbon/<species>`): each partner's own colour, for its name plate. Light enough for `on-ribbon` lettering. No dark variant.
- **Species tints** (`PartnerTint/<species>`): the pastel ground behind each partner. No dark variant: the figure keeps its own ground.
- **Sprout Green** (`sprout`), **Pip Yellow** (`pip`), **Pebble Blue-Grey** (`pebble`): accent tints for toggles and badges. Their names date from the first partners.

### Tertiary
- **Coral** (`protein`), **Sunflower** (`carbs`), **Sky** (`fat`): one ribbon per macro in the targets card. They have no dark variant and always carry ink lettering.

### Neutral
- **Lilac Ground** (`ground` / `ground-dark`): the background of every screen, the navigation bar, list backgrounds (the system grouped background is hidden) and the bottom action bars.
- **Card White** (`card` / `card-dark`): cards, list rows, secondary buttons and the primary button's label.
- **Track Lilac** (`track` / `track-dark`): disabled primary buttons, steps still to do, the in-card name plate and the 1 pt edge of the secondary button.
- **Soft Ink** (`ink-soft` / `ink-soft-dark`): section footers, picker detail lines, unit suffixes, disabled labels and the spinner. It stays above 4.5:1 on the ground in both modes. The system secondary grey reaches only about 2.8:1 there.
- **On-Ribbon Ink** (`on-ribbon`): lettering on every ribbon and name plate, and the partners' eyes and mouths. It is the same dark plum in both modes, because ribbons do not change with the appearance.
- **Card Shadow** (`card-shadow` / `card-shadow-dark`): the soft shadow under cards and secondary buttons, and the ground shadow under each partner.

### Named Rules
**The Ink-Not-Blue Rule.** The app tint is `ink`. No control shows system blue; the UIKit back button gets `ink` explicitly because it ignores the SwiftUI tint.

**The Ink-On-Ribbon Rule.** Text on a ribbon colour is always `on-ribbon` dark plum, in light and dark mode. Ribbons never carry white text.

**The No-Gradient Rule.** Every interface fill is one flat colour. Only the partner renders carry 3D light and shadow.

## Typography

**Display Font:** SF Pro Rounded (the system font with `.rounded` design, applied app-wide with `.fontDesign(.rounded)`)
**Body Font:** SF Pro Rounded
**Label/Mono Font:** none distinct; numbers use `.monospacedDigit()`

**Character:** One rounded family with a wide range of weights. Heavy gives names and numbers a chunky, sticker-like presence, and regular weight keeps the body text quiet.

### Hierarchy
- **Display** (Heavy, `.largeTitle`, 34 pt at the default size): the welcome title, the verify-email title, and large navigation titles (capped at 40 pt).
- **Numeral Large** (Heavy, `.largeTitle`, tabular): the kcal target on the targets card.
- **Headline** (Heavy, `.headline`, 17 pt): name plates and in-list headers such as "how it was calculated".
- **Label** (Bold, `.headline`): text on primary and secondary buttons, and inline navigation titles (capped at 22 pt).
- **Numeral** (Heavy, `.title3`, 20 pt, tabular): grams on the macro ribbons. Profile values use Heavy at the row's body size, also tabular.
- **Label Small** (Bold, `.subheadline`, 15 pt): macro names on the ribbons.
- **Title** (Regular, `.title3`, 20 pt): the welcome tagline. Number entry fields use `.title3` Semibold, tabular.
- **Body** (Regular, `.body`, 17 pt): list rows, consent text, explanations.
- **Caption** (Regular, `.footnote`, 13 pt): catalog card notes, picker detail lines, warnings, inline messages.

### Named Rules
**The Heavy Numbers Rule.** Every number the user reads as a result (kcal, grams, BMR, TDEE, factors) is Heavy, tabular and in ink.

**The Capped Bar Rule.** Navigation titles follow the text size at launch up to a cap: inline at 22 pt, large at 40 pt. A bar has a fixed height, and a title that keeps growing gets cut off. Body content has no cap.

## Layout

The page margin is 16 pt (`spacing.l`) on all scrolling content and bottom bars. Spacing uses a 4 pt scale (4, 8, 12, 16, 24, 32). Inside cards, groups use 12 pt and the lines within a group use 8 pt. Catalog cards sit 12 pt apart. The welcome sections are 24 pt apart.

- **Welcome:** title and tagline, then the catalog of sixteen partners as a grid of tiles, four in a row (two at accessibility sizes). The sign-in actions (Apple, Google, e-mail) are pinned at the bottom in a ground-coloured safe-area inset, 12 pt apart.
- **Onboarding:** one inline-titled list step per screen on the ground. A bottom bar holds the progress pills (one 8 pt capsule per step, 4 pt apart) above the full-width primary button. Steps after consent are pushed, so the back button and edge swipe work.
- **Profile (daily target):** large title, the targets card in the first section header, extended outward by 16 pt so it lines up with the list rows, then calculation rows and an Account row. "Adjust" sits in the toolbar as a menu.
- Forms and lists hide the system grouped background and use the ground. Rows sit on `card`.

### Accessibility sizes
At accessibility text sizes (`dynamicTypeSize.isAccessibilitySize`):
- The welcome catalog becomes a single column, and the sign-in actions move from the pinned bottom inset into the scroll view below the catalog. Pinned, they would cover most of the screen.
- Macro ribbons stack: the grams move under the macro name instead of being squeezed beside it.
- The Sign in with Apple button scales with the text (`@ScaledMetric` relative to `.headline`, from 54 pt) and stops at 80 pt (`ButtonMetrics.largestHeight`). Its label is drawn by the system.

## Elevation & Depth

The app is mostly flat, with one soft lift. Cards and secondary buttons rest on a diffuse, offset-down shadow in `card-shadow`. Catalog cards, list rows, ribbons and name plates have no shadow; they stand out by tonal contrast. In dark mode the shadow becomes 50% black and almost disappears, so the card colour (one step lighter than the ground) and the secondary button's track edge carry the separation.

### Shadow Vocabulary
- **Card lift** (radius 12, y 4, `card-shadow`): the targets card.
- **Button lift** (radius 6, y 2, `card-shadow`): secondary capsule buttons.
- **Ground shadow** (flat ellipse in `card-shadow`, 60 × 6.4 units under the feet): under every partner.

### Named Rules
**The Opaque Bar Rule.** Navigation bars use the opaque ground colour with no hairline. Nothing in the app is frosted or translucent.

## Shapes

Everything is rounded. Cards use 24 pt continuous corners. Ribbons use 22 pt continuous corners, half of their 44 pt minimum height, so a one-line ribbon is a capsule and a stacked ribbon becomes a rounded block. Buttons, name plates and progress pills are true capsules. The Sign in with Apple button is clipped to a capsule as well, which the HIG allows, so it lines up with the app's own buttons. There are no square corners and no hairline borders, except the 1 pt track edge on secondary buttons.

## Components

### Buttons
Chunky, full-width capsules that press in slightly.
- **Shape:** capsule, 54 pt minimum height (`ButtonMetrics.height`), full width, 16 pt horizontal padding, centred multi-line label.
- **Primary:** `ink` fill with a `card`-coloured Bold headline label. Used for the one main action of a screen (Continue, Finish, form submits).
- **Primary disabled:** `track` fill with an `ink-soft` label, so the next step stays visible and readable.
- **Pressed (both):** scale to 0.97 with ease-out over 0.15 s.
- **Secondary:** `card` fill, `ink` label, button lift shadow, and a 1 pt `track` edge that keeps it recognisable in dark mode. Disabled turns the label `ink-soft`.
- **Submit button:** the primary style with a soft-ink spinner beside the label while a request runs (the form disables it in the meantime).
- **Sign in with Apple:** the system button, black in light mode and white in dark mode, clipped to a capsule, the same height as the other buttons.

### Name Plate
A heavy label on a capsule of ribbon colour.
- **In the catalog:** species ribbon fill, `on-ribbon` Heavy headline, 12 × 4 pt padding, and a 2 pt white edge.
- **Inside a card:** no edge (`edge: nil`). A white edge cannot be seen on a white card in light mode and glares in dark mode. The "per day" plate on the targets card uses `track` fill with `ink` text.

### Cards / Containers
- **Partner hero (partner tab):** the species tint, 24 pt corners, 16 pt padding: the moving partner at 200 × 200 pt, the name plate, one line on how it is doing and why, and the level ribbon (level in Heavy, XP towards the next level as an `ink` bar on a `card` track).
- **Figure tile (welcome catalog):** the partner, square, on its species tint with 14 pt corners and 4 pt padding. VoiceOver reads its name, with its line of character as the hint.
- **Targets card:** `card` fill, 24 pt corners, 16 pt padding, card lift shadow. From top to bottom: an in-card name plate, the kcal target in Numeral Large, then three macro ribbons 12 pt apart.
- **Macro ribbon:** full-width, 44 pt minimum height, 22 pt corners, 16 × 8 pt padding. Macro fill with `on-ribbon` lettering: the name in Label Small and the grams in Numeral, on one baseline. They stack at accessibility sizes. In phase 2 the ribbons will fill up as the day is logged.
- **List rows:** `card` on the ground, the system inset-grouped shape.

### Inputs / Fields
- Number fields use `.title3` Semibold tabular in `ink`, with the unit in `ink-soft` beside them. Selection lists are inline pickers on card rows with an `ink` checkmark and an optional `ink-soft` footnote detail line. Birth date uses the wheel picker.

### Navigation
- System `NavigationStack`, opaque `ground` bar, no shadow line. Titles are SF Rounded in `ink`: inline Bold headline (max 22 pt), large Heavy large title (max 40 pt). Toolbar items and the back button are `ink`.

### Partner Figure
The signature component. The sixteen partners are soft 3D vinyl-toy figures, rendered in Blender from code (`design/partners/nieuw/partners_3d.py`) and stacked in SwiftUI (`Figures.swift`).
- **Layers:** per species and form, a `body` with its contact shadow, a `face` per mood, and one layer per accessory. All come from one camera and one scale, so they line up pixel-exactly. Order from back to front: body, face, then backpack, scarf, glasses, bow, cap, crown, and the sweatband.
- **Six forms, a strength ladder:** 1 a round baby that is nearly all head; 2 small limbs; 3 its own head and torso and the first signature feature; 4 upright on real legs with adult markings and a brow; 5 muscular, with a V-shaped chest and a wide stance; 6 the champion, flexing one arm. Each species adds its own feature: horns for the lamb, a crest for the penguin, a spike mane for the hedgehog, and so on. The catalog shows form 3.
- **Faces per mood:** content is the catalog face; happy has slightly larger eyes and an open smile with a tongue; sluggish has the lids half down and a flat mouth; tired has droopy lids and a small frown; hungry has big eyes with an extra highlight and an open mouth; asleep has closed eyes as arcs and a small round mouth, with two Z's in `ink` above the head (`PartnerAnchors.json`).
- **Shape:** `bodyShape` (0 lean, 1 round) widens the whole stack: 92 % of the catalog width when lean, 120 % when round.
- **Colours:** colour 0 is the species' own render. The other four turn the hue of the body layer (40°, 150°, 210°, 300°); the face and what is worn keep their colours. 1 and 2 can be chosen at once; 3 and 4 unlock at level 5 and 12.
- **Workout bonus:** a white sweatband with a red stripe.
- **Movement:** the partner bobs and squashes a little as it lands, faster and higher with more energy; asleep it only breathes. With Reduce Motion on it stands still, and the catalog never moves.
- **Light and dark:** the renders are the same in both modes; the species tint behind them carries the card.

### Progress Pills
- One capsule per onboarding step, 8 pt high, filling the width. Done and current steps are `ink`; the rest are `track`. VoiceOver reads them as one "step n of m" label.

## Do's and Don'ts

### Do:
- **Do** use `ground` behind every screen and hide the system grouped background on lists (`groundBackground()`).
- **Do** put text on ribbons and name plates in `on-ribbon`, whatever the colour scheme.
- **Do** set result numbers in Heavy with `.monospacedDigit()`.
- **Do** use `ink-soft` (`footerStyle()`) for footers and secondary lines, never the system secondary grey.
- **Do** give every new layout an accessibility-size variant that stacks or scrolls instead of truncating.
- **Do** make new partners, faces and accessories in the generator and render every layer from the same camera and fit, then run `scripts/partner-assets.py`.
- **Do** use the 4 pt spacing tokens and the `Radius` tokens; use continuous corners for rounded rectangles.

### Don't:
- **Don't** use gradients, glassmorphism or frosted bars.
- **Don't** use emoji as icons; icons are SF Symbols.
- **Don't** put a white edge on a name plate that sits inside a card.
- **Don't** let a partner's colours change with the appearance.
- **Don't** let navigation titles grow past 22 pt (inline) or 40 pt (large).
- **Don't** put AI-generated imagery or food photos into the partner world.

## Open Items

Gaps between the direction contract (`.impeccable/surfaces/fitling.md`) and the phase-1 build, recorded as-is:

1. **Active state colour.** The contract says "the active cell takes its ribbon colour". In the build, selected and done states are `ink` (picker checkmarks, progress pills, primary button). Only the consent toggle uses a ribbon colour (`sprout`). The rule is not implemented and is not canonized above.
2. **White edge on name plates.** The contract's variant B removes the sticker edge from the partners, and the drawing has none. The catalog name plates still carry a 2 pt white edge, which `NamePlate.swift` itself describes as "like a sticker". Confirm whether the plate edge belongs to the world. The verify-email badge also uses a one-off 3 pt white edge around a `pip` circle; it is not recorded as a rule.
3. **Apple button on Delete Account.** `DeleteAccountView` fixes the Apple button at 54 pt. Unlike the welcome screen, it does not grow with the text up to 80 pt.
4. **System fallback screens.** The configuration-error screen (`FitlingApp.swift`) uses the system background instead of `ground`. The connection screen uses `ground`.

# Fitling web fase 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Het tabblad Partner werkt in de browser zoals in de iOS-app: groei, stemming, accessoires, kleuren, niveau en XP, en de partner beweegt.

**Architecture:** Het verwerken van afgelopen dagen (`CreatureEngine.advance`) en de regels voor accessoires gaan via de WebAssembly-brug, zodat web en iPhone dezelfde partner uitrekenen. Wat het web uitrekent schrijft het naar `creatures` volgens de sync-afspraken. `advance` is bepaald door staat en dagen, dus twee apparaten die tegelijk verwerken schrijven hetzelfde. Het web verwerkt, net als iOS (`PartnerViewModel.refresh`), bij het openen van de app en als het tabblad terugkomt.

**Tech Stack:** zoals fase 2; geen nieuwe pakketten.

**Spec:** `docs/superpowers/specs/2026-11-24-fitling-web-design.md` (fase 3).

## Global Constraints

- Branch `web-fase-3`, vanaf `web-fase-2`; PR naar `web-fase-2`.
- Teksten via `t()`; de sleutels van iOS (`partner.*`) hergebruiken.
- Sync-afspraken zoals fase 2. `equipped_items` in de vaste volgorde van `CreatureItem.allCases`, zodat twee apparaten dezelfde rij schrijven.
- Elke regel die op iOS en web hetzelfde moet uitkomen, staat in FitlingCore; een iOS-wijziging gaat met `[ios]` in de laatste commit.
- Herinneringen blijven op het web weg tot fase 7 (Web Push); een schakelaar zonder werking is er niet.
- Toegankelijkheid zoals fase 1 en 2, plus `prefers-reduced-motion`: de partner staat dan stil.

## Review Focus

- **Twee apparaten verwerken tegelijk:** dezelfde dagen leveren dezelfde XP en vorm op, en nooit dubbel. Getest in Task 2 (`advancingTwiceWritesOnce`).
- **Een partner die lang niet verwerkt is:** alle dagen sinds de laatste verwerking tellen mee, ook als dat meer dan 1000 invoerregels zijn. Getest in Task 2 (`manyDaysAreReadInPages`).
- **Pet en kroon:** de een gaat af als de ander opgaat, ook als de andere op een ander apparaat werd opgezet. Getest in Task 1 en Task 4.
- **Een vergrendelde kleur of een vergrendeld accessoire:** niet te kiezen, met het niveau waarop het vrijkomt. Getest in Task 4.
- **"Beweging beperken" en 200 % tekst:** stilstaande partner, niets buiten beeld. Getest in Task 3 en Task 5.

---

### Task 1: Accessoires en de partner voor het web in FitlingCore

**Files:**
- Modify: `Packages/FitlingCore/Sources/FitlingCore/CreatureTypes.swift` of een nieuw `CreatureItems.swift`; `Fitling/Features/Partner/PartnerViewModel.swift`
- Modify: `web/core/Sources/FitlingWeb/FoodCalls.swift` (of een nieuw `PartnerCalls.swift`), `CallsTests.swift`, `web/src/core/fitlingCore.ts` en test
- Test: `Packages/FitlingCore/Tests/FitlingCoreTests/CreatureItemsTests.swift`

**Interfaces:**
- Produces (Swift): `CreatureItem.blocked: CreatureItem?` (verhuist uit de app) en `public static func CreatureEngine.wearing(_ worn: [CreatureItem], toggling item: CreatureItem, unlocked: [CreatureItem]) -> [CreatureItem]` — vergrendeld verandert niets; pet en kroon sluiten elkaar uit; uitkomst in de volgorde van `allCases`.
- Produces (brug):
  - `partnerSnapshot` krijgt erbij: `xp`, `xpIntoLevel`, `xpForNextLevel`, `unlockedItems`, `lockedColorLevels`, `todayXP { logging, withinTarget, protein, workout }`;
  - nieuw `partnerAdvance({ creature, entries, workoutDays, periods, fallback, today })` → `{ creature, changed, events: { kind: "leveledUp" | "unlockedItem" | "unlockedColor" | "recoveryBonus", level?, item?, index?, xp? }[], firstDay }` met de dagen vanaf `(lastProcessedDay ?? createdOn) - (windowDays - 1)`;
  - nieuw `wearing({ worn, item, unlocked })` → `{ worn }`.

- [ ] **Step 1:** FitlingCoreTests rood: `lockedItemsCannotBeWorn`, `wearingACapTakesOffTheCrown`, `itemsAreKeptInTheirOwnOrder`.
- [ ] **Step 2:** bouwen; `PartnerViewModel.toggle` roept `wearing` aan. CI: `PartnerTests` van de app ongewijzigd groen.
- [ ] **Step 3:** brugtests (Swift en TypeScript), elk met de uitkomst van de engine zelf vergeleken: `partnerAdvanceIsTheEnginesOwn`, `todayXPIsTheEnginesOwn`, `wearingFollowsTheCore`. Commit met `[ios]`.

### Task 2: De partner verwerken en bewaren

**Files:**
- Modify: `web/src/data/creature.ts`; Test: `web/src/data/creature.test.ts` (unit) en een integratietest tegen de lokale Supabase

**Interfaces:**
- Produces:
  - `advancePartner(client, core, userID, today): Promise<{ partner: Partner; events: PartnerEvent[] }>`: leest de partner, de invoer per pagina van 1000 vanaf `firstDay`, de trainingsdagen, de perioden en het profiel; roept `partnerAdvance` aan en schrijft alleen bij `changed`.
  - `savePartner(client, userID, change: Partial<{ colorIndex; name; tone; items }>, now)`.

- [ ] **Step 1:** rood: `advanceIsAppliedAndSavedOnce`, `advancingTwiceWritesOnce` (twee keer na elkaar: de tweede schrijft niets), `manyDaysAreReadInPages` (unit met nep-client, 2500 regels), `finishedDaysAreReportedOnce`.
- [ ] **Step 2–4:** bouwen, CI groen. **Step 5:** commit.

### Task 3: De partner beweegt

**Files:**
- Create: `web/src/partner/motion.ts` met test; Modify: `web/src/partner/PartnerCanvas.tsx`, `web/src/styles.css`

**Interfaces:**
- Produces: `motion(energy: number, asleep: boolean): { period: number; lift: number; squash: number; breathe?: number }` volgens `PartnerMotion` — wakker: hoek `t · (2 + 4·energie)`, hoogte `0,8 + 2,4·energie` procent van de zijde, platdrukken 2 %; slapend: alleen ademen, 2,5 % met `1,2` per seconde. `PartnerCanvas` krijgt `energy?: number` en zet een CSS-animatie met die waarden; bij `prefers-reduced-motion` staat hij stil.

- [ ] **Step 1:** `motion.test.ts` rood: `aLivelyPartnerBobsFasterAndHigher`, `aSleepingPartnerOnlyBreathes`. **Step 2–4:** bouwen, groen. **Step 5:** commit.

### Task 4: Het tabblad Partner

**Files:**
- Create: `web/src/screens/Partner.tsx`, `web/src/screens/PartnerEdit.tsx`, `web/src/ui/LevelRibbon.tsx`; Modify: `web/src/Home.tsx` (tabblad Partner, verwerken bij openen en terugkomen), `web/src/screens/Day.tsx` (leest na het verwerken)
- Test: `web/e2e/partner.spec.ts`

Nagebouwd naar `PartnerTabView.swift`:
- de held: figuur van 200 px die beweegt, naamplaatje, stemming, en het niveaulint met XP;
- "Vandaag verdien je" met de vier regels;
- accessoires als schakelaars, de vergrendelde met hun niveau;
- kleuren met slotjes en hun niveau;
- "Aanpassen" met naam en toon in een blad;
- nieuws na het verwerken als melding.

- [ ] **Step 1:** `partner.spec.ts` rood: `todayShowsWhatIsEarnedSoFar`, `wearingACapTakesOffTheCrown` (partner op niveau 15 via `xp`), `lockedItemsShowTheirLevel`, `lockedColoursCannotBeChosen`, `renameAndToneAreSaved`, `finishedDaysBringNewsOnce` (drie dagen op doel, daarna de melding één keer), `vandaagShowsTheProcessedPartner`.
- [ ] **Step 2–4:** bouwen, CI groen. **Step 5:** commit.

### Task 5: Audit, borden, review, PR

- [ ] **Step 1:** `audit.spec.ts`: het tabblad Partner en het blad Aanpassen in licht, donker en 200 %, plus `prefers-reduced-motion` (geen animatie).
- [ ] **Step 2:** borden naast `licht-12-partner`, `voeding-licht-7-partner` en de rondleiding van iOS; naar de gebruiker.
- [ ] **Step 3:** eindreview door een aparte reviewer, herstelronde met een test per punt.
- [ ] **Step 4:** PR `web-fase-3`.

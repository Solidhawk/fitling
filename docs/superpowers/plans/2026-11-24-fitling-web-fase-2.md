# Fitling web fase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Vandaag, loggen (zoeken, recent en favoriet, portie, eigen product), scannen en water werken in de browser zoals in de iOS-app, op dezelfde Supabase.

**Architecture:** De regels die nu in de iOS-views en `FoodDiary` zitten, verhuizen eerst naar FitlingCore, met de bestaande app-tests als bewijs dat er niets verandert. De webapp roept ze aan via de WebAssembly-brug van fase 0 en schrijft direct naar Supabase volgens de sync-afspraken. Waar de iPhone "op het apparaat" zoekt, zoekt het web in de eigen producten en de producten die de gebruiker al eens logde.

**Tech Stack:** Swift 6 (FitlingCore, `web/core`), TypeScript, React 18.3.1, Vite 6.3.5, Vitest 3.2.4, Playwright 1.53.1, `@supabase/supabase-js` 2.50.0, `lucide-react` 0.460.0, `@zxing/browser` 0.1.5 met `@zxing/library` 0.21.3 (MIT) voor scannen waar `BarcodeDetector` ontbreekt.

**Spec:** `docs/superpowers/specs/2026-11-24-fitling-web-design.md` (fase 2), naast `docs/ARCHITECTURE.md` §5 (producten).

## Global Constraints

- Branch `web-fase-2`, vanaf `web-fase-1`; PR naar `web-fase-1` (of naar main als #25 en #26 er al in zitten).
- Geen hardcoded teksten: alles via `t()` uit `Localizable.xcstrings` (nl, en, de). Bestaande sleutels van iOS hergebruiken.
- Sync: `updated_at` = klok van de client; verwijderen = `deleted_at` zetten; ids zijn client-UUID's; lezen filtert `deleted_at is null`.
- Geen migratie. Lezen en schrijven binnen de bestaande row level security (eigen rijen; gedeelde producten alleen lezen).
- Elke regel die op iOS en web hetzelfde moet uitkomen, staat in FitlingCore; TypeScript rekent niet zelf.
- Een iOS-wijziging gaat met `[ios]` in het bericht van de laatste commit, zodat de iOS-job draait.
- Toegankelijkheid zoals fase 1: axe zonder overtredingen, 44 px tikvlakken, licht, donker en 200 % tekst zonder iets buiten beeld.
- Iconen uit Lucide; geen emoji als icoon.
- Alleen `fitling-dev`; `lookup-product` op het echte project zetten alleen met akkoord.

## Review Focus

- **Middernacht en tijdzone:** een maaltijd gelogd om 23.59 hoort bij die dag; "Vandaag" volgt de klok van de browser. Getest in Task 4 (`dayFollowsTheBrowsersDate`).
- **Loggen zonder verbinding:** een foutmelding, niets half opgeslagen, de portie blijft staan. Getest in Task 5 (`loggingWithoutAConnectionKeepsThePortion`).
- **Twee apparaten tegelijk:** water uit twee bronnen telt op (losse rijen), een verwijderde invoer verdwijnt op beide. Getest in Task 3 (`waterFromTwoDevicesAddsUp`).
- **Een product zonder kcal of met onbekende macro's:** eerst de kcal van de verpakking, en het dagoverzicht meldt de onbekende macro's. Getest in Task 5 en Task 4.
- **Lange namen en merken bij 200 %:** niets buiten beeld in de lijsten, de portie en het eigen product. Getest in Task 7 (audit).

---

### Task 1: Regels voor loggen naar FitlingCore

**Files:**
- Create: `Packages/FitlingCore/Sources/FitlingCore/FoodLog.swift`, `Packages/FitlingCore/Tests/FitlingCoreTests/FoodLogTests.swift`
- Modify: `Fitling/Data/FoodDiary.swift`, `Fitling/Features/Log/PortionViewModel.swift`, `Fitling/Features/Log/AddProductViewModel.swift`
- Modify: `web/core/Sources/FitlingWeb/Calls.swift`, `web/core/Tests/FitlingWebTests/CallsTests.swift`, `web/src/core/fitlingCore.ts`, `web/src/core/fitlingCore.test.ts`

**Interfaces:**
- Produces (Swift, `public enum FoodLog`):
  - `static func searchKey(_ text: String) -> String` — kleine letters zonder accenten, getrimd (vervangt `FoodDiary.searchKey`; gebruikt `folded`).
  - `static let recentLimit = 20`; `static func recentProductIDs(_ logged: [(productID: UUID, updatedAt: Date)]) -> [UUID]` — nieuwste eerst, elk product één keer, hoogstens 20.
  - `static func storedName(_ name: String) -> String` (hoogstens 200 tekens), `static func storedQuantity(_ quantity: Double) -> Double` (één decimaal).
  - `struct Portion { init(quantityUnit: String, servingSize: Double?); let units: [QuantityUnit]; let defaultUnit: QuantityUnit; let defaultQuantity: Double; static func preview(per100: NutrientsPer100, quantity: Double?, unit: QuantityUnit, servingSize: Double?) -> Nutrients?; static func canSave(preview: Nutrients?, needsKcal: Bool, kcalOnPackage: Double?) -> Bool }` — de regels van `PortionViewModel` (portie > 0 en ≤ `Limits.foodQuantity`; kcal van de verpakking binnen `Limits.kcalPer100`).
  - `struct OwnProductDraft { name, brand, gtin: String; isMillilitre: Bool; servingSize, kcal, protein, carbs, fat: Double?; func validated() -> OwnProductFields? }` met `OwnProductFields { name, brand?, gtin?, quantityUnit, servingSize?, kcal100, protein100?, carbs100?, fat100?, searchName }` — de grenzen en afrondingen van `AddProductViewModel`.
- Produces (brug): `searchKey`, `recentProducts`, `portion`, `logEntry`, `ownProduct`, `dayTotals` en `barcode` (`Barcode.normalized`, nog niet in de brug); TypeScript-typen met dezelfde namen in `fitlingCore.ts`.

- [ ] **Step 1: FitlingCoreTests rood**

```swift
@Test func searchKeyFoldsCaseAndAccents() { #expect(FoodLog.searchKey("  Crème Brûlée ") == "creme brulee") }
@Test func recentShowsEachProductOnceNewestFirst() // a@3, b@2, a@1 → [a, b]; 25 verschillende → 20
@Test func portionStartsAtOneServingOrHundred() // servingSize 30 → [.serving, .gram], 1; "ml" zonder portie → [.millilitre], 100
@Test func aPortionNeedsAPositiveAmountWithinTheLimit() // 0 → nil, 10_001 → nil
@Test func withoutKcalThePackageValueDecides() // needsKcal, kcalOnPackage 950 → false, 250 → true
@Test func ownProductUsesTheDatabaseLimits() // de gevallen van AddProductTests.valuesOutsideTheDatabaseLimitsBlock en aBarcodeIsOptionalButMustBeValid
@Test func ownProductRoundsAsTheDatabaseStores() // kcal 123.45 → 123.5, protein 1.234 → 1.23, searchName "eigen granola merk"
```

- [ ] **Step 2:** `swift test` in `Packages/FitlingCore` via CI-job `core`. Expected: FAIL, "cannot find 'FoodLog'".
- [ ] **Step 3:** `FoodLog.swift` schrijven; de drie iOS-bestanden roepen het aan in plaats van hun eigen regels.
- [ ] **Step 4:** CI `core`, `web-core` en `ios` groen; `FoodLogTests` van de app ongewijzigd groen.
- [ ] **Step 5:** Brug: `CallsTests` per functie (rood, dan groen) en `fitlingCore.test.ts` met dezelfde waarden. Commit met `[ios]`.

### Task 2: Dagen van de partner naar FitlingCore

**Files:**
- Create: `Packages/FitlingCore/Sources/FitlingCore/DayRecords.swift`, test in `Packages/FitlingCore/Tests/FitlingCoreTests/DayRecordsTests.swift`
- Modify: `Fitling/Data/CreatureHistory.swift` (records via FitlingCore), brug en `fitlingCore.ts`

**Interfaces:**
- Produces: `public enum DayRecords { static func build(entries: [LoggedDay], workoutDays: Set<Day>, targets: (Day) -> NutritionTargets) -> [DayRecord] }` met `public struct LoggedDay { day: Day; kcal: Double; proteinG: Double? }` — één record per dag met eten of training, gesorteerd, kcal en eiwit afgerond zoals nu.
- Produces (brug): `partnerSnapshot({ state, entries, workoutDays, periods, fallback, today })` → `{ mood, energy, level, growthStage, unlockedColorCount }` via `CreatureEngine.snapshot`, met `targetsOnDay` per dag. Alleen lezen: XP en groei bijwerken is fase 3.

- [ ] **Step 1:** `DayRecordsTests.recordsCompareEachDayWithItsOwnTarget` en `aWorkoutDayWithoutFoodStillCounts` rood.
- [ ] **Step 2:** Bouwen; `CreatureHistory.records` gebruikt `DayRecords.build`. CI: `PartnerTests` (CreatureHistoryTests) ongewijzigd groen, iOS-job groen.
- [ ] **Step 3:** Brugtest `partnerSnapshotIsTheEnginesOwn`: een partner met drie dagen op doel geeft dezelfde stemming als `CreatureEngine.snapshot`. Commit met `[ios]`.

### Task 3: Dagboek en producten in de webapp

**Files:**
- Create: `web/src/data/diary.ts`, `web/src/data/products.ts`, `web/src/data/lookup.ts`, tests `web/src/data/diary.test.ts`, `web/src/data/lookup.test.ts`

**Interfaces:**
- Consumes: Task 1 (`searchKey`, `recentProducts`, `logEntry`, `ownProduct`, `barcode`).
- Produces:
  - `entriesOn(client, userID, day): Promise<FoodEntryRow[]>`, `waterOn(...)`, `addWater(client, userID, day, ml = 250, now)`, `deleteEntry(client, id, now)`.
  - `logProduct(client, core, userID, product, portion, meal, day, now): Promise<FoodEntryRow>`; gooit `Error("error.server")` of `Error("error.network")`.
  - `recentProducts`, `favoriteProducts`, `isFavorite`, `setFavorite` (favoriet uit = `deleted_at`).
  - `searchProducts(client, core, query): { own: Product[]; online: Product[] }` — eigen producten en eerder gelogde producten direct; gedeelde producten pas vanaf 3 tekens, hoogstens 30, zonder dubbele (`LogFoodViewModel.onlineSearchMinimum/onlineSearchLimit`); `%`, `_` en `\` letterlijk.
  - `ownCopy(...)`, `addOwnProduct(...)`.
  - `lookUp(client, core, scanned): Promise<{ kind: "found"; product } | { kind: "notFound" | "unavailable"; gtin } | { kind: "invalid" }>` — eerst een eigen of verse gedeelde rij (30 dagen), anders `lookup-product`; offline met een oude rij = gevonden.

- [ ] **Step 1:** Vitest-integratietests (lokale Supabase, `describe.skipIf` zoals `auth.test.ts`), elk naar het iOS-geval: `loggingStoresASnapshotOfNameAndValues`, `servingsUseTheServingSize`, `unknownMacrosAreStoredAsUnknown`, `recentShowsEachProductOnce`, `favoritesCanBeSetAndCleared`, `searchFindsOwnProductsFirstAndAddsOnlineOnes`, `aShortQueryStaysLocal`, `aSearchTermIsTakenLiterally` (`50%` vindt geen alles), `waterFromTwoDevicesAddsUp`, `deletedEntriesDisappear`, en voor `lookUp` de gevallen van `ProductLookupTests` (fresh, stale, offline met en zonder kopie, misread komt niet bij de server, UPC onder 13 cijfers, eigen product eerst). De Edge Function wordt in de unit-test vervangen door een nep-`invoke`.
- [ ] **Step 2:** CI rood. **Step 3:** bouwen. **Step 4:** CI groen. **Step 5:** commit.

### Task 4: Vandaag

**Files:**
- Create: `web/src/screens/Day.tsx`, `web/src/ui/DayCard.tsx`, `web/src/ui/SwipeRow.tsx`; Modify: `web/src/Home.tsx` (tabblad Vandaag), `web/src/ui/MacroBlocks.tsx` (variant gegeten-van-doel, zoals `MacroBlocks(eaten:targets:)`)
- Test: `web/e2e/day.spec.ts`

**Interfaces:**
- Consumes: Task 2 `partnerSnapshot`, Task 3 dagboek, `targetsOnDay`, `dayTotals`.
- Produces: `Day({ userID })`; opent `LogFood` (Task 5) als blad met `meal` en `day`.

Nagebouwd naar `DayView.swift`: de kaart in de tint van de partner (figuur 112 px, naamplaatje, kcal te gaan of over het doel, "gegeten van", stemming), de voetnoot met onbekende macro's, water met "+ glas" (250 ml), per maaltijd de invoer met kcal en "Toevoegen", vorige en volgende dag (volgende uit op vandaag), titel "Vandaag" of de weekdag met datum. Verwijderen: vegen naar links toont "Verwijderen", zoals `onDelete`; met toetsenbord of schermlezer staat de knop na de rij en wordt zichtbaar bij focus.

- [ ] **Step 1:** `day.spec.ts` rood: `usesTheTargetsThatAppliedOnThatDay` (twee perioden), `reportsUnknownMacros`, `waterAddsUp`, `mealsAreKeptApartAndDeletedEntriesDisappear`, `theFutureCannotBeShown`, `dayFollowsTheBrowsersDate` (klok via `page.clock` op 23.59 en 00.01), `theCardShowsThePartnersMood`.
- [ ] **Step 2–4:** bouwen, CI groen, schermafbeeldingen naast `licht-11-vandaag`, `voeding-*-1-vandaag-leeg` en `voeding-*-5-vandaag-gelogd` van iOS. **Step 5:** commit.

### Task 5: Loggen, portie en eigen product

**Files:**
- Create: `web/src/screens/LogFood.tsx`, `web/src/screens/Portion.tsx`, `web/src/screens/AddProduct.tsx`, `web/src/ui/ProductRow.tsx` (met de letter-placeholder van `ProductThumbnail`)
- Test: `web/e2e/log.spec.ts`

**Interfaces:**
- Consumes: Task 1 (`portion`, `logEntry`, `ownProduct`), Task 3.
- Produces: `LogFood({ meal, day, onLogged })` als blad met eigen stapel (zoeken → portie → eigen product), terug via `useHistoryStack`.

Nagebouwd naar `LogFoodView`, `PortionView` en `AddProductView`: zoekveld, rijen "Scannen" en "Eigen product", secties favoriet en recent, "Op dit apparaat" en "Online" (het web noemt de eerste sectie zoals iOS; de sleutels blijven `log.results.device` en `log.results.online`), niets gevonden met een knop naar eigen product; de portie met eenheden, aantal, kcal van de verpakking, wat het toevoegt, onbekende macro's en favoriet.

- [ ] **Step 1:** `log.spec.ts` rood: `logAProductFromSearch`, `servingsUseTheServingSize`, `productWithoutKcalAsksForIt` (eigen kopie, gedeelde rij ongewijzigd), `favoriteShowsUpAtTheTop`, `recentShowsEachProductOnce`, `aShortQueryStaysLocal`, `addAnOwnProductAndLogIt`, `loggingWithoutAConnectionKeepsThePortion` (`page.route` breekt `food_entries` af).
- [ ] **Step 2–4:** bouwen, CI groen. **Step 5:** commit.

### Task 6: Scannen

**Files:**
- Create: `web/src/screens/Scan.tsx`, `web/src/scan/camera.ts`; Modify: `web/package.json` (`@zxing/browser` 0.1.5, `@zxing/library` 0.21.3)
- Test: `web/e2e/scan.spec.ts`

**Interfaces:**
- Consumes: Task 3 `lookUp`.
- Produces: `Scan({ onCode })`: camera via `getUserMedia` (achtercamera), `BarcodeDetector` waar die er is (EAN-13, EAN-8, UPC-A, UPC-E), anders `@zxing/browser`; zonder camera of toestemming de tekst `scan.unavailable`; altijd het veld om de code te typen (`scan.manual.field`, `scan.manual.submit`).

Uitkomsten zoals `LogFoodViewModel.handleScan`: gevonden → portie; onbekend → melding met "Toevoegen" (eigen product met de streepjescode ingevuld); geen verbinding → melding; misread → niets, de scanner zoekt verder.

- [ ] **Step 1:** `scan.spec.ts` rood met getypte codes en `page.route("**/functions/v1/lookup-product")`: `scanOfAKnownProductOpensThePortion`, `scanOfAnUnknownProductOffersToAddIt`, `misreadIsIgnored`, `scanWhileOfflineKeepsTheBarcode`, `withoutACameraTheCodeCanBeTyped`. De camera zelf is in CI niet te testen; dat staat in de PR voor een test op de iPhone.
- [ ] **Step 2–4:** bouwen, CI groen. **Step 5:** commit.

### Task 7: Audit, borden, review, PR

- [ ] **Step 1:** `audit.spec.ts` uitbreiden met Vandaag, het logblad, de portie, het eigen product en scannen, in licht, donker en 200 %, met een product met een lange naam en merk.
- [ ] **Step 2:** Vergelijkingsborden met de iOS-schermafbeeldingen van de laatste iOS-run (`voeding-*`, `rondleiding-01..03`, licht, donker en grootste tekst); naar de gebruiker.
- [ ] **Step 3:** Eindreview door een aparte reviewer (Review Focus hierboven), herstelronde met een test per punt.
- [ ] **Step 4:** PR `web-fase-2`; borden en de vraag om de camera op een iPhone te proberen erbij.

# Fitling web fase 6: Boodschappen — implementatieplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** de boodschappenlijst van de iPhone 1 op 1 op het web, geopend vanuit het tabblad Menu. Het scherm bevat:
- de lijst in looproutevolgorde: afvinken, weghalen, toevoegen, afgevinkte items weghalen;
- "Alles voor het weekmenu";
- de aanbiedingen van de eigen supermarkten: goedkoopste per item met geldigheid, totaal per winkel, twijfelgevallen bevestigen;
- "Mijn supermarkten";
- delen met een code: uitnodigen, meedoen, leden, lijst verlaten.

**Architecture:** zoals Menu in fase 5. De logica van `ShoppingStore` en `ShoppingViewModel` verhuist naar FitlingCore als één waarde `ShoppingBook`. iOS bouwt hem uit SwiftData en schrijft zelf; het web bouwt hem uit Supabase en schrijft met supabase-js. Het gaat om deze regels:
- de volgorde van de items;
- wat een nieuwe vulling vanuit het menu weghaalt en toevoegt;
- welke aanbiedingen bij welk item horen;
- het totaal per winkel;
- de vragen bij twijfel;
- een geldige itemnaam.

Delen gaat via de bestaande RPC's `create_shopping_list_invite` en `join_shopping_list` en de tabel `shopping_list_members`.

**Tech Stack:** Swift 6 (FitlingCore, WASM-brug), React 18 + TypeScript, supabase-js, Vitest, Playwright.

**Spec:** `docs/superpowers/specs/2026-11-24-fitling-web-design.md` (fase 6).

## Global Constraints

- **FitlingCore:** rekenregels die op iOS en web hetzelfde moeten uitkomen staan daar. iOS roept ze daarna aan, en `ShoppingTests`/`OfferMatcherTests` blijven groen.
- **Teksten:** geen hardcoded teksten. `shopping.*` bestaat al in `Localizable.xcstrings`.
- **Database:** de database verandert niet. Leden staan in `shopping_list_members` (zonder `synced_at`). Items en lijsten volgen de sync: client-UUID, `updated_at` als klok van de client, `updated_by` is de gebruiker, en verwijderen is `deleted_at` zetten.
- **Aanbiedingen:**
  - Een prijs wordt alleen getoond als hij hooguit 26 uur oud is (`fetched_at`, voorwaarde van PrijsProfeet), en altijd met "t/m".
  - Onder de aanbiedingen staat de bronvermelding met een link van minstens 44 px hoog.
  - Bevestigde twijfelgevallen blijven op het toestel (`fitling.confirmedOffers`).
- **Kerntypen:** namen die de synclaag van de app nog niet gebruikt (`ShoppingItemRow`, `OfferRow`, `SupermarketRow`, `ShoppingBook`).

## Review Focus

- **Delen:** twee leden zien en wijzigen dezelfde items, en iemand zonder code ziet niets. Test in Task 3 (`aSharedListIsSeenByBothMembers`).
- **Foute code:** een foute of verlopen code zegt dat, en een volle lijst zegt dat ook. Test in Task 3 (`aWrongCodeSaysSo`).
- **Opnieuw vullen vanuit het menu:**
  - de vorige menu-items gaan eraf;
  - eigen items en afgevinkte menu-items blijven.

  Test in Task 1 (`refillingKeepsOwnAndCheckedItems`).
- **Twijfelgevallen** tellen pas mee na "Klopt". Een aanbieding van een andere winkel of een verlopen aanbieding telt niet. Test in Task 1 (`uncertainOffersCountOnlyWhenConfirmed`).
- **200 % tekst en donker** op elk scherm. Test in Task 5 (audit).

---

### Task 1: ShoppingBook in FitlingCore, iOS roept hem aan [ios]

**Files:**
- Create `Packages/FitlingCore/Sources/FitlingCore/ShoppingBook.swift` en `Packages/FitlingCore/Tests/FitlingCoreTests/ShoppingBookTests.swift`.
- Modify `Fitling/Data/ShoppingStore.swift` en `Fitling/Features/Shopping/ShoppingViewModel.swift`.

**Interfaces:**
- **Rijen:**
  - `ShoppingItemRow {id, name, quantity?, unit?, aisle, productID?, isChecked, source}`
  - `OfferRow {id, supermarketID, title, brand?, gtin?, quantityValue?, quantityUnit?, priceCents, validFrom: Day, validTo: Day}`
  - `SupermarketRow {id, name}`
  - `RecipeIngredientRow {recipeID, productID?, name: LocalizedText, quantity, unit, aisle, position}`
- **`ShoppingBook(items:, offers:, supermarkets:, favoriteSupermarketIDs:, confirmedOfferIDs:, today:)`** met:
  - `items()`: niet afgevinkt eerst, dan looproute (`ShoppingListBuilder.aisleOrder`), dan naam.
  - `offers() -> ShoppingOffers {cheapest: [UUID: OfferMatch], totals: [StoreTotal], questions: [OfferQuestion {itemName, offerTitle, supermarketIDs, offerIDs}]}`. Alleen favorieten, en winkelnamen tellen niet mee als woord. Vragen gaan per itemnaam en titel, alleen voor items zonder prijs, met winkels op naam.
  - `refill(with lines: [ShoppingLine]) -> ShoppingChange {removed: [UUID], added: [ShoppingLine]}`.
  - `static itemName(_ text:) -> String?`: getrimd, hooguit 120 tekens, leeg wordt nil.
- **`MenuBook.shoppingLines(ingredients: [RecipeIngredientRow]) -> [ShoppingLine]`:** de maaltijden van vandaag t/m +6 die nog niet gelogd zijn, met de namen in de taal van de gebruiker.

- [ ] Rood: `itemsComeUncheckedFirstInShopOrder`, `refillingKeepsOwnAndCheckedItems`, `uncertainOffersCountOnlyWhenConfirmed`, `questionsGroupByItemAndTitle`, `menuLinesSkipLoggedMeals`, `anItemNameIsTrimmedAndBounded`.
- [ ] Bouwen.
- [ ] ShoppingStore en ShoppingViewModel erop zetten.
- [ ] CI core en iOS groen.

### Task 2: De brug voor Boodschappen

**Files:**
- Create `web/core/Sources/FitlingWeb/ShoppingCalls.swift`.
- Modify `Calls.swift`, `CallsTests.swift` en `web/src/core/fitlingCore.ts` (+ test).

**Aanroepen:**
- `shoppingOverview(ShoppingInput)` geeft `{items: [{id, name, amount?, isChecked, offer?: {priceCents, supermarketName, validTo}}], totals: [{supermarketID, name, totalCents, itemsWithoutPrice}], questions: [...]}`.
- `shoppingRefill({shopping: ShoppingInput, menu: MenuInput, ingredients})` geeft `{removed, added}`.
- `shoppingItemName({text})` geeft `{name?}`.

- [ ] Rood: `shoppingOverviewMatchesTheCore`, `refillFromTheMenu`.
- [ ] Bouwen.
- [ ] CI web-core groen.

### Task 3: Boodschappen lezen en schrijven op het web

**Files:** Create `web/src/data/shopping.ts` (+ `shopping.test.ts` tegen de lokale Supabase).

**Functies:**
- `ensureList(client, userID, name, ownerName, now)`: de eerste lijst op naam, anders een nieuwe met de gebruiker als eigenaar.
- `loadShopping(client, listID, today)`: items, leden, supermarkten, favorieten, en de aanbiedingen van de favorieten. Gepagineerd, `valid_to >= today`, `fetched_at` hooguit 26 uur oud.
- `addItem`, `toggleItem`, `removeItem`, `clearChecked`, `applyShoppingChange`.
- `setFavoriteSupermarket`.
- `loadRecipeIngredients(client, recipeIDs)`.
- `createInvite`, `joinList(client, code, name)`: `invalid_invite` en `list_full` worden `shopping.error.*`.
- `leaveList`.

- [ ] Rood: `aSharedListIsSeenByBothMembers`, `aWrongCodeSaysSo`, `oldOffersAreLeftOut`, `refillingFromTheMenuReplacesMenuItems`.
- [ ] Bouwen.
- [ ] CI groen.

### Task 4: De schermen

**Files:**
- Create `web/src/screens/Shopping.tsx`: de lijst, de aanbiedingen, de leden, een blad om mee te doen, en een blad met supermarkten.
- Modify:
  - `web/src/screens/Menu.tsx`: de rij Boodschappen met winkelwagen, boven Recepten.
  - `web/src/ui/Alert.tsx`: een eigen label voor de knop zonder actie ("OK" bij de uitnodigingscode).
- Test `web/e2e/shopping.spec.ts` en de audit.

- [ ] Rood: `addingCheckingAndClearing`, `theMenuFillsTheList`, `offersShowWithTheirValidity`, `inviteAndJoin`, en de audit-schermen.
- [ ] Bouwen.
- [ ] CI groen.

### Task 5: Audit, borden, review, PR

- [ ] Audit licht/donker/200 %.
- [ ] Borden naast `rondleiding-18/19/20` en `toegankelijkheid-scherm-boodschappen`.
- [ ] Eindreview door een verse reviewer; Important fixen.
- [ ] UNFORGET.
- [ ] PR web-fase-6 → web-fase-5.

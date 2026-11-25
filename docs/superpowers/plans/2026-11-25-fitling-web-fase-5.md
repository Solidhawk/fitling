# Fitling web fase 5: Menu — implementatieplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** het tabblad Menu van de iPhone 1 op 1 op het web: het weekmenu per dag (vastzetten, wisselen, verwijderen, met één tik loggen, een dag vernieuwen), een menu maken (dagen, doel, voorkeuren), voorkeuren, recepten (lijst, recept, eigen recept maken en verwijderen).

**Architecture:** zoals Training in fase 4. De logica van `MenuStore` (welke maaltijden blijven en welke komen bij een nieuw menu of een vernieuwde dag, de volgorde van recepten en maaltijden, welke recepten passen bij een maaltijd, de waarden van een gelogde maaltijd, wanneer een eigen recept compleet is) verhuist naar FitlingCore als één waarde `MenuBook` met alle rijen. iOS bouwt hem uit SwiftData en schrijft zelf; het web bouwt hem uit Supabase, vraagt de uitkomsten via de brug en schrijft met supabase-js.

**Tech Stack:** Swift 6 (FitlingCore, WASM-brug), React 18 + TypeScript, supabase-js, Vitest, Playwright.

**Spec:** `docs/superpowers/specs/2026-11-24-fitling-web-design.md` (fase 5).

## Global Constraints

- Rekenregels die op iOS en web hetzelfde moeten uitkomen staan in FitlingCore; iOS roept ze daarna aan (iOS-tests `MenuTests` e.a. ongewijzigd groen).
- Geen hardcoded teksten (`menu.*`, `meal.*` bestaan al in `Localizable.xcstrings`).
- Gedeelde recepten (`owner_id` null, gezaaid uit `supabase/seed/recipes.sql`) zijn alleen-lezen; eigen rijen krijgen een client-UUID; verwijderen = `deleted_at`.
- Kerntypen krijgen namen die de synclaag van de app niet al gebruikt (`MenuRecipe`, `MenuEntry`, `MenuSettings`, `MenuBook`).
- Boodschappen (de link in het tabblad) komt in fase 6: in fase 5 ontbreekt die rij.
- Eén-tik-loggen maakt één `food_entries`-rij met `recipe_id`, eenheid `serving`, en zet `logged_entry_id`; een tweede tik doet niets.

## Review Focus

- Een nieuw menu laat vastgezette en gelogde maaltijden staan en vervangt de rest; een vernieuwde dag raakt andere dagen niet. Test in Task 1 (`pinnedAndLoggedMealsStay`, `renewingADayLeavesTheOthers`).
- Twee keer tikken op loggen logt één keer. Test in Task 4 (`loggingTwiceLogsOnce`).
- Een eigen recept zonder titel, maaltijd of macro's kan niet worden bewaard. Test in Task 1 en Task 4.
- Een recept dat niet meer bestaat (verwijderd op een ander apparaat) laat het menu niet vastlopen. Test in Task 4.
- 200 % tekst en donker op elk scherm. Test in Task 5 (audit).

---

### Task 1: MenuBook in FitlingCore, iOS roept hem aan [ios]

**Files:** Create `Packages/FitlingCore/Sources/FitlingCore/MenuBook.swift`, `Packages/FitlingCore/Tests/FitlingCoreTests/MenuBookTests.swift`; Modify `Fitling/Data/MenuStore.swift`, `Fitling/Features/Menu/MenuViewModel.swift`.

**Interfaces:**
- Rijen: `MenuRecipe {id, ownerID?, title: LocalizedText, servings, cookMinutes, kcalPerServing, proteinGPerServing, carbsGPerServing, fatGPerServing, costCentsPerServing?, keepsWell, mealSlots: [String], tags: [String], productIDs: [UUID]}`; `MenuEntry {id, plannedOn: Day, meal: String, recipeID, servings, isLeftover, isPinned, loggedEntryID?}`; `MenuSettings {excludedTags, maxCookMinutes?, budgetCents?, mealPrep, mealSlots}`.
- `MenuBook(userID:, recipes:, entries:, settings:, excludedProductIDs:, today:, languages:)` met `static menuDays = 7`, `recipes()` (op titel, gevouwen), `entries()` (vandaag t/m +6, per dag en maaltijdvolgorde), `recipes(for entryID:)`, `generate(days:seed:targets:) -> MenuChange`, `renew(_ day:seed:targets:) -> MenuChange` (`MenuChange {removed: [UUID], added: [PlannedMeal], issues: [MenuIssue]}`), `loggedMeal(_ entryID:) -> LoggedMeal? {name, day, slot, servings, kcal, proteinG, carbsG, fatG}`, `static ownRecipeIsComplete(...)`.

- [ ] Rood: `pinnedAndLoggedMealsStay`, `renewingADayLeavesTheOthers`, `entriesComeByDayAndMeal`, `aLoggedMealHasTheRecipesValuesForItsServings`, `anOwnRecipeNeedsTitleMealsAndMacros`; dan bouwen; MenuStore/MenuViewModel erop; CI core en iOS groen.

### Task 2: De brug voor Menu

**Files:** Create `web/core/Sources/FitlingWeb/MenuCalls.swift`; Modify `Calls.swift`, `CallsTests.swift`, `web/src/core/fitlingCore.ts` (+ test).

Aanroepen: `menuOverview(MenuInput) -> {days: [{day, entries: [{id, slot, recipeID, title, servings, kcal, isPinned, logged}]}], recipes: [{id, title, kcalPerServing, cookMinutes, own}]}`, `menuGenerate(MenuInput & {days, seed, targets})`, `menuRenew(MenuInput & {day, seed, targets})` → `{removed, added, issues}`, `menuLoggedMeal(MenuInput & {entryID})`, `menuRecipesFor(MenuInput & {entryID})`, `menuTargets({goal?, body, periods, fallback, today}) -> Targets`, `ownRecipeComplete(...)`. Seeds als string (UInt64 past niet in een JS-getal).

- [ ] Rood: `menuGenerateKeepsPinnedMeals`, `loggedMealIsTheBooksOwn`, `menuTargetsFollowTheGoal`; bouwen; CI web-core groen.

### Task 3: Menu lezen en schrijven op het web

**Files:** Create `web/src/data/menu.ts` (+ `menu.test.ts` tegen de lokale Supabase).

`loadMenu(client)`, `applyMenuChange(client, userID, change, now)`, `setPinned`, `swapRecipe`, `removeEntry`, `logMeal(client, userID, entry, meal, now)` (food entry + `logged_entry_id`, tweede keer niets), `loadPreferences`/`savePreferences`, `createRecipe`, `deleteRecipe`.

- [ ] Rood: `aNewMenuIsStoredAndPinnedMealsStay`, `loggingTwiceLogsOnce`, `ownRecipesAreSavedAndRemoved`; bouwen; CI groen.

### Task 4: De schermen

**Files:** Create `web/src/screens/Menu.tsx`, `MenuGenerator.tsx`, `MenuPreferences.tsx`, `RecipePicker.tsx`, `Recipes.tsx` (lijst, recept, eigen recept); `web/src/ui/RecipeThumbnail.tsx`; SwipeRow met acties links en rechts, lang indrukken voor het menu; Modify `Home.tsx`; Test `web/e2e/menu.spec.ts`.

- [ ] Rood: `aMenuIsMadeForTheChosenDays`, `pinnedMealsStayWhenTheMenuIsRenewed`, `aMealIsLoggedWithOneTap`, `aMealIsSwappedForAnotherRecipe`, `anOwnRecipeIsMadeAndShown`, `preferencesAreSaved`; bouwen; CI groen.

### Task 5: Audit, borden, review, PR

- [ ] Audit van alle menuschermen in licht, donker en 200 %; borden met de iOS-screenshots; eindreview (subagent, opus), fixronde; kleine punten naar UNFORGET; PR `web-fase-5` → `web-fase-4`.

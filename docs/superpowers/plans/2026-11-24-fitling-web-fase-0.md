# Fitling web, fase 0: fundament — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Een lege Fitling-webapp met de tabbalk, live op GitHub Pages, die de rekenregels van FitlingCore als WebAssembly kan aanroepen en zijn teksten, kleuren en beelden uit de iOS-bestanden haalt.

**Architecture:** De map `web/` bevat drie delen:
- een Swift-pakket `web/core` dat FitlingCore (via een pad) als WebAssembly-reactor bouwt, met drie geëxporteerde functies en JSON erin en eruit;
- een Node-script dat Localizable.xcstrings, colorsets en beelden omzet;
- een React-app (Vite, TypeScript).

CI bouwt alles in een nieuwe job "Web" en publiceert vanaf `main` naar GitHub Pages. De iOS-app en `Packages/FitlingCore` veranderen niet.

**Tech Stack:**
- Swift 6.4 met de Swift SDK voor WebAssembly (`wasm32-unknown-wasi`);
- `@bjorn3/browser_wasi_shim`;
- Node 22, React 18, Vite, TypeScript, Vitest, Playwright, `@axe-core/playwright`, `lucide-react`;
- GitHub Actions en GitHub Pages.

**Spec:** `docs/superpowers/specs/2026-11-24-fitling-web-design.md` (D-24 in `docs/ARCHITECTURE.md`)

## Global Constraints

- **Geen hardcoded teksten:** elke tekst die de gebruiker ziet komt via `t()` uit de gegenereerde catalogus. Brongegevens: `Fitling/Resources/Localizable.xcstrings`, `sourceLanguage` = `nl`. Talen: nl, en, de.
- **Geen geheimen in `web/`:** ook geen Supabase-gegevens in fase 0.
- **Alleen gratis software met een vrije licentie.** De letter van SF wordt niet meegestuurd: `font-family: system-ui` en `ui-rounded`.
- **Iconen uit `lucide-react`**, nooit SF Symbols.
- **Uiterlijk volgens DESIGN.md:** lila grond (donker: diep pruim), inkt, witte kaarten.
- **Toegankelijkheid:** tikvlakken ≥ 44 px, contrast WCAG AA, `prefers-reduced-motion` en `prefers-color-scheme` gevolgd, maten in `rem` zodat tekst meegroeit.
- **Breedte:** op brede schermen staat de app in een kolom van hoogstens 480 px.
- **Bouwen en testen alleen in GitHub Actions:** lokaal is Windows zonder Swift. Commits naar CI eindigen niet met `[ios]`, want de iOS-job is voor deze fase niet nodig.
- **Elke commit eindigt met** `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

- **Browsertaal buiten nl/en/de** (bijv. `fr-FR`): de app valt terug op Nederlands, zoals de catalogus. Getest in Task 2 (`fallsBackToDutch`).
- **Een sleutel zonder Engelse of Duitse vertaling:** de bouw faalt met de sleutel in de melding, in plaats van een lege tekst te tonen. Getest in Task 2 (`failsOnMissingTranslation`).
- **Donkere modus:** de grond wordt diep pruim en de inkt licht. Getest in Task 3 (`darkModeUsesDarkTokens`).
- **Ongeldig verzoek aan de rekenregels** (onbekende functie, kapotte JSON): het antwoord is `{"error": …}`, geen crash van de WebAssembly. Getest in Task 1 (`unknownFunctionIsAnError`, `brokenJSONIsAnError`).
- **De tabbalk op een iPhone met thuisbalk:** de knoppen staan boven `env(safe-area-inset-bottom)`. Getest in Task 3 (`tabBarRespectsSafeArea`, berekende stijl).

---

### Task 1: FitlingCore als WebAssembly, met het dagdoel als proef

**Files:**
- Create: `web/core/Package.swift`
- Create: `web/core/Sources/FitlingWeb/Bridge.swift` (de drie exports)
- Create: `web/core/Sources/FitlingWeb/Calls.swift` (verzoek naar FitlingCore en terug)
- Test: `web/core/Tests/FitlingWebTests/CallsTests.swift`
- Create: `web/src/core/fitlingCore.ts`
- Test: `web/src/core/fitlingCore.test.ts`
- Modify: `.github/workflows/ci.yml` (job `web`, eerste stappen)
- Modify: `docs/superpowers/specs/2026-11-24-fitling-web-design.md` (één zin: de brug is drie eigen exports in plaats van JavaScriptKit)

**Interfaces:**
- Produces (Swift):
  - `handle(_ request: Data) -> Data`;
  - de exports `fitling_alloc(_ size: Int32) -> Int32`, `fitling_free(_ pointer: Int32, _ size: Int32)` en `fitling_call(_ pointer: Int32, _ length: Int32) -> Int64` (bovenste 32 bits: pointer naar het antwoord, onderste 32 bits: lengte).
- Request: `{"fn": "dailyPlan", "input": {...}}`.
- Produces (TS):
  - `loadCore(wasm: ArrayBuffer): Promise<FitlingCore>`;
  - `interface FitlingCore { dailyPlan(input: DailyPlanInput): DailyPlan }`;
  - `DailyPlanInput = { birthDay: string; sex: "male" | "female" | "other"; heightCm: number; weightKg: number; activityLevel: "sedentary" | "light" | "moderate" | "active" | "very_active"; goal: "lose" | "build_muscle" | "maintain" | "recomp"; today: string }` (dagen als `"2026-11-18"`);
  - `DailyPlan = { bmr: number; tdee: number; targets: { kcal: number; proteinG: number; carbsG: number; fatG: number }; floorApplied: boolean; warnings: string[] }`.
- Fouten: `dailyPlan` gooit `Error(message)` als het antwoord `{"error": message}` is.

- [ ] **Step 1: Schrijf de Swift-tests** in `CallsTests.swift`:
  - `dailyPlanMatchesTheApp`: verzoek met `birthDay "1996-01-10"`, `male`, `180`, `80`, `moderate`, `maintain`, `today "2026-11-18"`. Verwacht:
    - `targets == {kcal 2760, proteinG 128, carbsG 389, fatG 77}`;
    - `bmr` binnen 0,0001 van 1780;
    - `floorApplied == false` en `warnings` leeg.
    - Dezelfde waarden als `NutritionEngineTests.maintenanceTargetEqualsTotalExpenditure`.
  - `unknownFunctionIsAnError`: `{"fn":"nope","input":{}}` → `{"error":"unknown function nope"}`.
  - `brokenJSONIsAnError`: `Data("{".utf8)` → een object met de sleutel `error`.
- [ ] **Step 2: Laat CI de tests rood zien.** Maak `web/core/Package.swift` aan:
  - één library-target `FitlingWeb` (afhankelijk van `.package(path: "../../Packages/FitlingCore")`);
  - een executable-product `fitling-core`;
  - het testtarget.

  Voeg in `ci.yml` de job `web` toe (`runs-on: ubuntu-latest`, `container: swift:6.4`) met als stap `swift test` in `web/core`. Push op branch `web-fase-0`.

  Verwacht: FAIL, want `handle` bestaat niet.
- [ ] **Step 3: Implementeer `handle` in `Calls.swift`.**
  - Decodeer het verzoek. Bij `dailyPlan` maak je `BodyProfile` en `Day(isoString:)` en roep je `NutritionEngine.plan(for:on:)` aan.
  - Codeer `EnergyPlan` als `DailyPlan`; `warnings` als rawValues, gesorteerd.
  - Elke fout wordt `{"error": "<beschrijving>"}`.

  Zet de exports in `Bridge.swift` met `@_expose(wasm, "fitling_call")` enz.:
  - `fitling_alloc` en `fitling_free` beheren het geheugen voor JS;
  - het antwoord blijft staan tot JS `fitling_free` aanroept.
- [ ] **Step 4: Run in CI.** Verwacht: de drie tests PASS en de bestaande job "FitlingCore (Linux)" ongewijzigd groen.
- [ ] **Step 5: Bouw de WebAssembly in CI.**
  - Stap in job `web`: installeer de Swift SDK voor WebAssembly die bij 6.4 hoort. URL en checksum staan op swift.org bij "Swift SDKs"; zet beide letterlijk in `ci.yml`.
  - Bouw met:
    ```bash
    swift build --swift-sdk wasm32-unknown-wasi -c release --product fitling-core -Xswiftc -Xclang-linker -Xswiftc -mexec-model=reactor
    ```
  - Kopieer het resultaat naar `web/public/fitling-core.wasm` en upload het als artefact `fitling-core-wasm`.

  Verwacht: een `.wasm` van enkele MB, die `fitling_call` exporteert (`wasm-objdump` is niet nodig; Task 1 Step 7 bewijst het).
- [ ] **Step 6: Schrijf de TS-test** in `fitlingCore.test.ts` (Vitest, Node). Lees `public/fitling-core.wasm` in, `loadCore`, en roep `dailyPlan` aan met de invoer van Step 1. Verwacht dezelfde `targets` (2760/128/389/77). Een tweede test: `dailyPlan` met `goal: "x"` gooit een `Error`.
- [ ] **Step 7: Implementeer `loadCore` in `fitlingCore.ts`.**
  - Instantieer met `@bjorn3/browser_wasi_shim`, roep `_initialize` aan en schrijf het verzoek via `fitling_alloc`.
  - `fitling_call` splitst het `BigInt` in pointer en lengte. Lees het antwoord als UTF-8 en roep daarna `fitling_free` aan.

  Voeg `npm ci` en `npx vitest run` toe aan de job, ná het bouwen van de WebAssembly. Verwacht: PASS.
- [ ] **Step 8: Commit** (`feat(web): FitlingCore als WebAssembly, met het dagdoel als proef`). Pas daarbij de zin over JavaScriptKit in het ontwerp aan.

**Terugvaloptie:** lukt Step 5 niet binnen deze taak omdat de SDK of de reactor niet werkt, leg dan de foutmelding vast in het ontwerp en vervang Step 5–7:
- een Swift-test in `web/core` schrijft voor 50 profielen invoer en uitkomst naar `web/src/core/golden/dailyPlan.json`;
- `fitlingCore.ts` krijgt een TypeScript-versie van `NutritionEngine.plan` met dezelfde interface;
- de Vitest-test rekent alle 50 na.

### Task 2: Teksten, kleuren en beelden uit de iOS-bestanden

**Files:**
- Create: `web/scripts/generate.mjs` (Node, zonder dependencies). Export `generate({ resources, out })` en een CLI die `../Fitling/Resources` naar `src/generated` en `public` schrijft.
- Create: `web/src/i18n.ts`
- Test: `web/scripts/generate.test.mjs`, `web/src/i18n.test.ts`
- Create: `web/.gitignore` (`src/generated/`, `public/partners/`, `public/exercises/`, `public/recipes/`, `public/fitling-core.wasm`, `node_modules/`, `dist/`)

**Interfaces:**
- Produces:
  - `src/generated/strings.json`: `{ nl: Record<string, Entry>, en: …, de: … }` met `Entry = string | { one: string; other: string }`;
  - `src/generated/colors.css`: `:root { --ground: …; --ink: …; … }` en dezelfde namen in `@media (prefers-color-scheme: dark)`. Namen in kebab-case, bijv. `InkSoft` → `--ink-soft` en `PartnerRibbon/owl` → `--partner-ribbon-owl`;
  - `public/partners/<naam>.png`, `public/exercises/<id>.webp` met `ExerciseAnimations.json`, `public/recipes/<id>.jpg`, `src/generated/partnerAnchors.json`;
  - `t(key: string, ...args: (string | number)[]): string` en `language(): "nl" | "en" | "de"`.

- [ ] **Step 1: Schrijf de tests voor het script** (fixture-catalogus in de test, uitvoer naar een tijdelijke map):
  - `keepsPlainStrings`: een `stringUnit` per taal komt letterlijk mee;
  - `keepsPlurals`: `variations.plural.one/other` wordt `{one, other}`;
  - `failsOnMissingTranslation`: een sleutel zonder `en` laat `generate` falen met een fout waarin de sleutel staat;
  - `convertsColors`: componenten als `"0xEF"` en als `"0.937"` worden allebei `#EFxxxx`, en een colorset zonder donkere variant gebruikt licht ook in donker;
  - `copiesEveryLayerOnTheRealResources`: op de echte map komen 1344 partnerlagen, 114 bestanden in `exercises/` en een `.jpg` per map in `Assets.xcassets/Recipes` aan.
- [ ] **Step 2: Run** `npx vitest run scripts`. Verwacht: FAIL (geen `generate`).
- [ ] **Step 3: Implementeer `generate`.**
  - Partnerlagen: `Partners.xcassets/<soort>/<naam>.imageset/<naam>.png` → `partners/<naam>.png`.
  - Recepten: `Recipes/<id>.imageset/photo.jpg` → `recipes/<id>.jpg`.
  - Voeg `"generate": "node scripts/generate.mjs"` toe aan `package.json`, en laat `build` en `test` het eerst draaien.
- [ ] **Step 4: Schrijf de tests voor `t`** in `i18n.test.ts` (met de echte `strings.json`):
  - `t("tab.today")` → `"Vandaag"` bij `nl`.
  - `t("training.program.composed %lld", 2)` → `"Door de app samengesteld · 2 trainingen"`, en met 1 → `"… · 1 training"`.
  - `t("menu.unit.piece %@", "4")` → `"4 stuks"`.
  - `fallsBackToDutch`: met `navigator.languages = ["fr-FR"]` geeft `language()` `"nl"`; met `["de-AT", "en"]` geeft het `"de"`.
  - Een onbekende sleutel geeft de sleutel terug, zoals iOS doet.
- [ ] **Step 5: Implementeer `t` en `language`.**
  - Opmaakcodes `%@`, `%lld`, `%d` en de genummerde varianten (`%1$@`) worden in volgorde gevuld.
  - Meervoud kiest via `new Intl.PluralRules(language())` op het eerste getal in `args`.
  - Getallen worden opgemaakt met `Intl.NumberFormat(language())`.
- [ ] **Step 6: Run** `npx vitest run`. Verwacht: alles PASS.
- [ ] **Step 7: Commit** (`feat(web): teksten, kleuren en beelden uit de iOS-bestanden`).

### Task 3: De lege app met tabbalk, getest in de browser

**Files:**
- Create: `web/package.json`, `web/vite.config.ts` (`base: "/fitling/"`), `web/tsconfig.json`, `web/index.html` (`lang` gezet door de app, `viewport-fit=cover`, `theme-color` light/dark), `web/src/main.tsx`, `web/src/App.tsx`, `web/src/TabBar.tsx`, `web/src/styles.css`
- Test: `web/e2e/shell.spec.ts`, `web/playwright.config.ts` (projecten: `webkit` met iPhone 15 en `chromium` met Pixel 7; schermafbeeldingen naar `test-results/`)

**Interfaces:**
- Consumes: `t`, `language` (Task 2), `colors.css` (Task 2).
- Produces:
  - `<App />` met de state `tab: "today" | "training" | "menu" | "partner" | "target"`;
  - per tab een `<main>` met een grote titel (`h1`);
  - `TabBar` met `role="tablist"` en vijf knoppen met `role="tab"` en `aria-selected`.
- Titels en tabnamen:
  - `tab.today` (Vandaag), icoon `Utensils`;
  - `training.title`, icoon `Dumbbell`;
  - `menu.title`, icoon `CookingPot`;
  - `partner.title`, icoon `Smile`;
  - `profile.title` (Dagdoel), icoon `PieChart`.

- [ ] **Step 1: Schrijf de Playwright-tests** in `shell.spec.ts`:
  - `showsFiveTabs`: vijf `tab`-rollen met de namen Vandaag, Training, Menu, Partner, Dagdoel; "Vandaag" is geselecteerd en de `h1` is "Vandaag".
  - `switchesTabs`: tik op "Dagdoel", dan is de `h1` "Dagdoel" en `aria-selected` verplaatst.
  - `darkModeUsesDarkTokens`: met `page.emulateMedia({ colorScheme: "dark" })` is de berekende `background-color` van `body` gelijk aan de donkere `Ground` uit `colors.css`, en met licht aan de lichte.
  - `tabBarRespectsSafeArea`: de berekende `padding-bottom` van de tabbalk bevat `env(safe-area-inset-bottom)`. Controleer via `getComputedStyle`, of lees de CSS-regel als de engine `env()` oplost naar 0.
  - `tabsAreBigEnough`: elke tab is minstens 44 × 44 px.
  - `noAccessibilityViolations`: `new AxeBuilder({ page }).analyze()` geeft 0 violations, in licht en donker.
  - `screenshots`: per tab een schermafbeelding, in licht en donker, met `page.screenshot` naar `test-results/screens/<tab>-<licht|donker>.png`.
- [ ] **Step 2: Run** `npx playwright test` in CI (job `web`, na `npm run build` en `npx playwright install --with-deps chromium webkit`, met `vite preview` als `webServer`). Verwacht: FAIL.
- [ ] **Step 3: Implementeer de app.**
  - Kleuren alleen via de variabelen uit `colors.css`.
  - De tabbalk staat vast onderaan met `padding-bottom: env(safe-area-inset-bottom)`. De actieve tab in inkt, de andere in `--ink-soft`.
  - Titels in `ui-rounded`, zwaar.
  - `document.documentElement.lang = language()`.
- [ ] **Step 4: Run** `npx playwright test`. Verwacht: PASS in `webkit` en `chromium`. Upload `test-results/screens` als artefact `web-screenshots`.
- [ ] **Step 5: Bekijk de schermafbeeldingen** (download het artefact) en stuur ze naar de gebruiker. Vergelijk ze met de iOS-schermafbeeldingen van de tabbladen (lila grond, inkt, titels). Elk verschil anders dan de iconen is een fout.
- [ ] **Step 6: Commit** (`feat(web): lege app met de vijf tabbladen`).

### Task 4: Publiceren op GitHub Pages

**Files:**
- Modify: `.github/workflows/ci.yml`:
  - in job `web`: op `main` `actions/upload-pages-artifact` met `web/dist`;
  - nieuwe job `pages`: `needs: web`, alleen bij een push naar `main`, `permissions: pages: write, id-token: write`, `environment: github-pages`, stap `actions/deploy-pages@v4`.

- [ ] **Step 1: Vraag de gebruiker** om in GitHub bij Settings → Pages de bron op "GitHub Actions" te zetten. Dat is een instelling van de repository: de gebruiker doet het zelf, of geeft akkoord dat Claude het doet met `gh api -X POST repos/Solidhawk/fitling/pages -f build_type=workflow`.
- [ ] **Step 2: Voeg de stappen toe** en open een PR van `web-fase-0` naar `main`. Verwacht: de job `web` is groen op de PR en `pages` wordt overgeslagen (geen `main`).
- [ ] **Step 3: Na de merge (met akkoord van de gebruiker)** draait `pages` op `main`. Verwacht: `https://solidhawk.github.io/fitling/` toont de app met de vijf tabbladen. Controleer met `curl -s -o /dev/null -w "%{http_code}"`: `200`, en open de pagina in de ingebouwde browser.
- [ ] **Step 4: Commit en documenteer.**
  - Zet in `docs/TASKS.md` een sectie "Web, fase 0 — gebouwd" met het adres en hoe je hem op het beginscherm zet.
  - Zet in UNFORGET de open punten:
    - het app-icoon;
    - de publishable key en het adres van `fitling-dev` als GitHub-variabelen (S10);
    - CORS in de Edge Functions (fase 1).

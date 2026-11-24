# Fitling web, fase 1: welkom, inloggen, onboarding, partner kiezen, Dagdoel en account — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Iemand kan op het web een account maken met e-mail, de onboarding doorlopen, een partner kiezen en zijn Dagdoel zien, aanpassen en zijn account beheren. Alles ziet er 1 op 1 uit als de iOS-app, met dezelfde getallen.

**Architecture:** Bovenop fase 0 (branch `web-fase-0`, PR #25, nog niet gemerged; de gebruiker wil offline blijven tot er echte schermen zijn).
- **Gegevens:** de webapp praat met Supabase via `@supabase/supabase-js`. In CI is dat een lokale Supabase (`supabase start`, met `schema.sql`), nooit het echte project.
- **Rekenregels:** komen via de WebAssembly-brug. Logica die in de iOS-app zit en de getallen bepaalt, verhuist eerst naar FitlingCore.
- **Schermen:** worden per stuk nagebouwd naar de SwiftUI-bron. Elk scherm wordt vergeleken met de iOS-schermafbeelding van dezelfde stap.

**Tech Stack:** zoals fase 0, plus `@supabase/supabase-js` en de Supabase CLI in CI.

**Spec:** `docs/superpowers/specs/2026-11-24-fitling-web-design.md` (D-24), Fase 1.

## Global Constraints

- Alles uit fase 0 blijft gelden:
  - teksten via `t()`;
  - kleuren uit `colors.css`;
  - `system-ui`/`ui-rounded`, Lucide-iconen;
  - 44 px tikvlakken, AA-contrast, `prefers-reduced-motion`;
  - kolom van 30 rem.
- **De iOS-bron is de waarheid** voor tekstsleutels, volgorde van velden, validatie en welke knop wanneer werkt. Bij twijfel: lees het SwiftUI-bestand en doe hetzelfde.
- **Getallen** komen uit FitlingCore via de brug, nooit uit nagebouwde TypeScript: dagdoel, macro's, waarschuwingen, eenheden, leeftijdscontrole en het dagdoel op een dag.
- **Schrijven naar Supabase volgt de sync-afspraken:**
  - de client zet `updated_at`;
  - verwijderen is `deleted_at`;
  - ids zijn client-UUID's.
- **Het echte Supabase-project wordt niet aangeraakt.** Testen gaat tegen de lokale Supabase in CI.
- **Geen publicatie:** `main` wordt niet gemerged zonder akkoord van de gebruiker.
- **Inloggen alleen met e-mail.** De knoppen voor Apple en Google staan er op het web niet.
- **Commits:** elke commit eindigt met `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Geen `[ios]`, tenzij FitlingCore of de iOS-app verandert.

## Review Focus

- **Een sessie die verloopt of uitlogt in een ander tabblad:** de app gaat terug naar Welkom, zonder een half scherm. Getest in Task 3 (`signedOutElsewhereReturnsToWelcome`).
- **Onboarding onder 18 jaar:** dezelfde blokkade en dezelfde knop "account verwijderen" als op iOS. Getest in Task 4 (`underageCannotContinue`).
- **Imperiale eenheden** (browser `en-US`): lengte in ft/in en gewicht in lb, met dezelfde omrekening als iOS. Getest in Task 4 (`imperialUnitsGiveTheSameProfile`).
- **Profiel opslaan mislukt** (geen verbinding): de foutmelding van iOS (`error.server`), en er gaat geen half profiel naar de server. Getest in Task 4 (`saveFailureShowsServerError`).
- **De grootste tekst en de donkere modus** op elk nieuw scherm. Axe-test en schermafbeeldingen per scherm in licht, donker en bij 200 % tekst, in Task 7.

---

### Task 1: Lokale Supabase voor de webtests, en de verbinding in de app

**Files:**
- Modify: `.github/workflows/ci.yml`
  - In job `web`: `supabase/setup-cli@v3`, `supabase start` en `schema.sql` laden zoals job `backend` dat doet.
  - Zet `VITE_SUPABASE_URL` en `VITE_SUPABASE_PUBLISHABLE_KEY` uit `supabase status -o env`; dat zijn de openbare sleutels van de lokale ontwikkelomgeving.
- Modify: `supabase/config.toml`: `http://localhost:4173/fitling/` bij `additional_redirect_urls`. Alleen lokaal; het echte project krijgt dit pas met akkoord.
- Create: `web/src/data/supabase.ts`: `export const supabase` via `createClient(url, key)`. Zonder env gooit het een duidelijke fout bij het bouwen.
- Create: `web/src/data/auth.ts`, met `AuthState` en `AuthService` (zie Interfaces).
- Test: `web/e2e/auth.spec.ts` en een helper `web/e2e/mail.ts`, die de bevestigingsmail uit de lokale Inbucket/Mailpit haalt (poort 54324).

**Interfaces:**
- `type AuthState`:
  - `{ kind: "loading" }`;
  - `{ kind: "signedOut" }`;
  - `{ kind: "awaitingEmailVerification"; email }`;
  - `{ kind: "signedIn"; userID: string; email: string }`.
- `class AuthService`:
  - `state`, `subscribe(listener)`;
  - `signUp(email, password)`, `signIn(email, password)`, `signOut()`;
  - `sendPasswordReset(email)`, `updatePassword(password)`, `resendVerification(email)`.
- **Foutsleutels** zijn die van `AuthService.swift`, bijvoorbeeld `auth.error.invalidCredentials` en `auth.reset.linkExpired`. Lees ze daar af; de web-sleutels zijn dezelfde.

- [ ] **Step 1: Schrijf de tests:**
  - `signUpNeedsTheEmailLink`: aanmelden geeft `awaitingEmailVerification`; de link uit de mail openen geeft `signedIn`.
  - `signInWithWrongPasswordShowsTheAppsError`.
  - `signOutReturnsToSignedOut`.
- [ ] **Step 2: Laat ze rood zien in CI** (job `web`). Verwacht: FAIL, want `AuthService` ontbreekt.
- [ ] **Step 3: Implementeer** `supabase.ts` en `auth.ts` met `supabase.auth` (`onAuthStateChange`, `persistSession: true`). De redirect is `location.origin + import.meta.env.BASE_URL`.
- [ ] **Step 4: Run in CI.** Verwacht: PASS. **Commit.**

### Task 2: Rekenregels voor onboarding en Dagdoel via de brug, met verhuizing naar FitlingCore

**Files:**
- Create: `Packages/FitlingCore/Sources/FitlingCore/TargetPeriods.swift`. De regel uit `LocalData.targets(on:for:)` als pure functie:
  - `TargetPeriods.targets(on day: Day, periods: [TargetPeriodRecord], fallback: NutritionTargets) -> NutritionTargets`;
  - `TargetPeriodRecord(effectiveOn: Day, updatedAt: Date, targets: NutritionTargets)`;
  - de laatste periode op of vóór de dag, en bij gelijke dag de nieuwste.
- Modify: `Fitling/Data/LocalData.swift`: `targets(on:for:)` roept `TargetPeriods.targets` aan. Commit met `[ios]`.
- Modify: `web/core/Sources/FitlingWeb/Calls.swift`, met de functies:
  - `bodyInput` (`BodyInput`: metrisch of imperiaal → `heightCm`, `weightKg`, `isValid`);
  - `birthDay` (`isValidBirthDay`, `isAdult`, `age`);
  - `macros`, `kcalShares`, `warnings`, `commonMinimumKcal`;
  - `targetsOnDay` (`TargetPeriods`);
  - `creatureStart` (`CreatureEngine.startShape`, het aantal kleuren bij niveau 1, `growthLevels`).
- Modify: `web/src/core/fitlingCore.ts`: een getypte functie per call.
- Test:
  - `Packages/FitlingCore/Tests/FitlingCoreTests/TargetPeriodsTests.swift`: dezelfde gevallen als de bestaande app-test van `targets(on:)`; zoek die in `FitlingTests`.
  - `web/core/Tests/FitlingWebTests/CallsTests.swift`: per call één bekend getal uit de bestaande FitlingCore-tests.
  - `web/src/core/fitlingCore.test.ts`: dezelfde getallen via de WebAssembly.

- [ ] **Step 1:** Rood: de FitlingCore-test voor `TargetPeriods` (bestaat niet).
- [ ] **Step 2:** `TargetPeriods` implementeren, en `LocalData` erop laten leunen. De bestaande app-tests moeten groen blijven (iOS-job).
- [ ] **Step 3:** Rood: de brugtests per call.
- [ ] **Step 4:** Calls implementeren. Fouten blijven `{"error"}`, en elke getalinvoer wordt eerst tegen `Limits` gecontroleerd.
- [ ] **Step 5:** Groen in CI, met de iOS-job. **Commit.**

### Task 3: Welkom, inloggen met e-mail en de routering

**Files:**
- Create: `web/src/screens/route.ts`:
  - `screenFor(state: AuthState, profile: Profile | null, creature: Creature | null, online: boolean): Screen`;
  - `Screen = loading | welcome | verifyEmail | needsConnection | onboarding | partnerSetup | home`;
  - volgens `RootViewModel.refresh`: zonder profiel naar onboarding; zonder partner naar partnerSetup; offline zonder bekend profiel naar needsConnection.
- Create: `web/src/data/profile.ts`: `loadProfile(userID)` en `loadCreature(userID)`.
- Create: `web/src/partner/PartnerCanvas.tsx` en `web/src/partner/framing.ts`, nagebouwd naar `Figures.swift`:
  - de lagen gestapeld;
  - de kleur met `filter: hue-rotate()`, met de hoeken uit `PartnerLayers.hues`;
  - framing uit `partnerAnchors.json`;
  - de stille houding, en de beweging uit `PartnerFigure`, uit bij `prefers-reduced-motion`.
- Create: `web/src/ui/NamePlate.tsx`, `web/src/ui/FigureTile.tsx`, `web/src/ui/Buttons.tsx` (de stijlen van `Buttons.swift`).
- Create: de schermen `web/src/screens/Welcome.tsx`, `EmailAuth.tsx`, `VerifyEmail.tsx`, `ResetPassword.tsx`, `NeedsConnection.tsx`. Nagebouwd naar `WelcomeView.swift`, `EmailAuthView.swift`, `PasswordViews.swift` en `RootView.swift`; dezelfde sleutels en identifiers.
- Test:
  - `web/src/screens/route.test.ts`: elke tak van `screenFor`;
  - `web/src/partner/framing.test.ts`: twee vormen met bekende uitkomst uit de Swift-tests van `PartnerFraming` (zoek ze in `FitlingTests`);
  - `web/e2e/welcome.spec.ts`:
    - de catalogus toont 16 partners met naam en hint;
    - aanmelden, bevestigen en daarna de onboarding;
    - `signedOutElsewhereReturnsToWelcome`;
    - schermafbeeldingen `welkom-licht/donker`.

- [ ] **Step 1:** Rood: `route.test.ts` en `framing.test.ts`.
- [ ] **Step 2:** `route.ts` en `framing.ts` implementeren. Groen. **Commit.**
- [ ] **Step 3:** Rood: `welcome.spec.ts` (de schermen ontbreken).
- [ ] **Step 4:** De schermen bouwen. Groen in CI.
- [ ] **Step 5:** Vergelijk de schermafbeeldingen met iOS (`licht-0-welkom`, `donker-0-welkom` uit de iOS-artefacten) in één bord, en stuur dat naar de gebruiker. **Commit.**

### Task 4: Onboarding, en het profiel opslaan

**Files:**
- Create: `web/src/screens/Onboarding.tsx`, nagebouwd naar `OnboardingFlowView.swift` en `OnboardingViewModel.swift`:
  - acht stappen in de volgorde van `Step`, met een voortgangsbalk;
  - `canContinue` per stap via de brug;
  - de onder-18-tak met "account verwijderen", die in Task 6 werkt;
  - het resultaat met `dailyPlan`, de vloer-melding en de waarschuwingen.
- Create: `web/src/data/saveProfile.ts`: `finishOnboarding(input) -> Promise<void>`.
  - Schrijft `profiles` en `target_history` (`effective_on` = vandaag, `updated_at` = nu).
  - Doet dat in één RPC of in twee upserts. Mislukt de tweede, dan wordt de eerste teruggedraaid door `deleted_at`. Kies de RPC als `schema.sql` er een heeft; anders de upserts.
- Test:
  - `web/e2e/onboarding.spec.ts`:
    - de hele flow zoals `OnboardingFlowTests`, met dezelfde waarden en uitkomst 2.760 kcal;
    - `underageCannotContinue`;
    - `imperialUnitsGiveTheSameProfile` (locale `en-US`);
    - `saveFailureShowsServerError` (route naar Supabase afgebroken via `page.route`);
    - schermafbeeldingen per stap.
  - `web/src/data/saveProfile.test.ts`: de rijen die worden verstuurd.

- [ ] **Step 1:** Rood: de tests.
- [ ] **Step 2:** Bouwen. Groen.
- [ ] **Step 3:** Vergelijkingsbord met iOS `licht-1`…`licht-8`. **Commit.**

### Task 5: Partner kiezen

**Files:**
- Create: `web/src/screens/PartnerSetup.tsx`, nagebouwd naar `PartnerSetupView.swift` en `PartnerSetupViewModel.swift`:
  - het raster van 16, met 3 kolommen en 2 bij grote tekst;
  - de voorvertoning in vorm 1, blij;
  - de naam, beperkt zoals `PartnerSetupViewModel.limited`;
  - de kleurstalen met slotjes;
  - de toon met de voorbeeldzinnen;
  - de knop "Klaar".
- Create: `web/src/data/saveCreature.ts`: `creatures` met `body_shape` = `creatureStart.startShape`, `created_on` = vandaag en `xp` 0.
- Test: `web/e2e/partner-setup.spec.ts`:
  - de uil kiezen, "Uil" aanvullen tot "Uiltje";
  - opslaan, en daarna het Vandaag-tabblad;
  - een naam van 25 tekens wordt afgekapt;
  - schermafbeeldingen.

- [ ] **Step 1:** Rood. **Step 2:** Bouwen. Groen. **Step 3:** Vergelijkingsbord met iOS `licht-9`/`licht-10`. **Commit.**

### Task 6: Dagdoel, profiel aanpassen, account en Over Fitling

**Files:**
- Create: `web/src/screens/Profile.tsx`, nagebouwd naar `ProfileView.swift`:
  - de opbouwkaart: BMR → × activiteit → TDEE → × doel → dagdoel;
  - de macroblokken, nagebouwd naar `MacroBlocks.swift`;
  - eiwit per kg, de voetnoot, de link Account en de knop "Aanpassen".
- Create: `web/src/screens/EditProfile.tsx`, nagebouwd naar `EditProfileView.swift` en `ProfileViewModel.swift`:
  - het profiel bijwerken;
  - eigen doelen met `macros` en `warnings`;
  - opslaan via `recordTargets`-gedrag: een tweede wijziging op dezelfde dag werkt dezelfde periode bij.
- Create:
  - `web/src/screens/Account.tsx`, nagebouwd naar `AccountView.swift`: e-mail, uitloggen, gegevens exporteren en account verwijderen;
  - `web/src/screens/About.tsx`, nagebouwd naar `AboutView.swift`, met "Website van …" als label;
  - `web/src/data/export.ts`, nagebouwd naar `DataExport`, met dezelfde JSON- en CSV-vorm. Zoek de tests in `FitlingTests/DataExportTests.swift` en neem hun gevallen over.
- Modify: `supabase/functions/delete-account` en `supabase/functions/lookup-product`: CORS-headers en het antwoord op `OPTIONS` (UNFORGET S35), met Deno-tests in de job `backend`.
- Test:
  - `web/e2e/profile.spec.ts`:
    - na de onboarding toont Dagdoel 2.760 kcal en 128/389/77 g;
    - aanpassen naar eigen doelen werkt;
    - exporteren geeft een bestand met het profiel;
    - account verwijderen leidt naar Welkom;
    - de onder-18-tak verwijdert het account.

- [ ] **Step 1:** Rood. **Step 2:** Bouwen. Groen. **Step 3:** Vergelijkingsbord met iOS `licht-13-dagdoel` en `rondleiding-26`…`29`. **Commit.**

### Task 7: Elk scherm van fase 1 in licht, donker en grote tekst

**Files:**
- Test: `web/e2e/fase1-audit.spec.ts`. Per scherm van fase 1:
  - axe in licht en donker;
  - een schermafbeelding bij `font-size: 200%`, als de lettergrootte van de browser;
  - een controle dat geen tekst wordt afgekapt: `scrollWidth <= clientWidth` voor tekst-elementen.

- [ ] **Step 1:** Run. Los elke bevinding op met een test die eerst faalt.
- [ ] **Step 2:** Groen. Eén eindbord van alle fase-1-schermen naast iOS, naar de gebruiker. **Commit.**
- [ ] **Step 3:** Eindreview en PR `web-fase-1` → `web-fase-0`, of naar `main` als PR #25 dan gemerged is. Niet mergen zonder akkoord.

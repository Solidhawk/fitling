# Fitling fase 1 – Implementatieplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Een iOS-app die bouwt en test op GitHub Actions, met inloggen (Apple, Google, e-mail), onboarding met toestemming en 18+-check, doelberekening, profiel bewerken, account verwijderen en offline-first profielsync met Supabase.

**Architecture:** SwiftUI + `@Observable` ViewModels op de main actor; SwiftData als lokale bron van waarheid; rekenregels in het pure Swift-pakket `FitlingCore` (getest op Linux); Supabase voor Auth, Postgres (RLS) en één Edge Function. Het Xcode-project wordt door XcodeGen gegenereerd op een macOS-runner.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, iOS 17, Swift Testing, supabase-swift 2.x, XcodeGen, Supabase CLI + pgTAP, Deno, Node (stringcheck), GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-18-fitling-architectuur-design.md` (verder: "ontwerp §n").

## Global Constraints

- iOS-deploymenttarget 17.0; Swift-taalmodus 6 (strict concurrency); `SWIFT_VERSION = 6.0`.
- Enige app-dependency: `supabase-swift`, product `Supabase`, exacte versie vastgezet in `project.yml`.
- Geen hardcoded UI-teksten: alles via `Fitling/Resources/Localizable.xcstrings`, ontwikkeltaal `nl`, plus `en` en `de`; semantische sleutels met prefix uit `common|welcome|auth|consent|onboarding|profile|targets|account|error`.
- Geen geheime sleutels in de app; alleen `SUPABASE_HOST` + `SUPABASE_PUBLISHABLE_KEY` via `Config/Supabase.xcconfig` (niet in git).
- Opslag altijd metrisch (kg, cm, kcal); weergave via `Measurement` + `Locale`.
- Enum-rawValues = SQL-checkwaarden: `male|female|other`, `sedentary|light|moderate|active|very_active`, `lose|build_muscle|maintain|recomp`.
- Grenzen (`FitlingCore/Limits.swift` = SQL-checks): lengte 100–250 cm, gewicht 30–350 kg, leeftijd ≥ 18, geboortedatum ≥ 1900-01-01, kcal 1–20 000, eiwit 0–1000 g, koolhydraten 0–5000 g, vet 0–2000 g.
- Geen TODO's, placeholders, dode knoppen of ongebruikte code (CLAUDE.md). Testgereedschap alleen in `Fitling/UITesting/`, alleen in DEBUG.
- Eigen kleurpalet (named colors, licht + donker), SF Symbols, Dynamic Type, 4-pt-spacing; geen gradients, geen glassmorphism, geen emoji als icoon.
- Toegankelijkheid: elke knop en elk icoon heeft een VoiceOver-label uit de catalog; tikvlakken minimaal 44 × 44 pt.
- Werk op branch `fase-1`. Linux-jobs draaien bij elke push; de macOS-job alleen op `main` of handmatig (`gh workflow run ci.yml --ref fase-1`). "Klaar" = alle jobs groen.

## Review Focus

1. **Geboortedatum bij een tijdzone ten westen van UTC** (bijv. `America/Los_Angeles`): de gekozen datum, de leeftijd en de opgeslagen `yyyy-MM-dd` blijven dezelfde dag. → test in Task 6.
2. **Invoer in pounds/feet bij `en_US`**: 176 lb wordt 79,8 kg opgeslagen en de grenzen worden in kg gecontroleerd. → test in Task 10.
3. **Dubbel tikken op een actieknop** (registreren, reset aanvragen, account verwijderen): er gaat maar één verzoek uit. → tests in Task 8 en Task 11.
4. **Server weigert een push** (geen netwerkfout, bijvoorbeeld een check-fout): `needsPush` blijft staan, er komt een melding, en er wordt niet eindeloos opnieuw geprobeerd. → test in Task 9.
5. **Grootste tekstgrootte (accessibility XXXL)**: in elke onboardingstap blijft de knop "Verder" bereikbaar (scrollt mee). → UI-test in Task 12.

---

## Voorbereiding (door de gebruiker, vóór Task 1)

- Privé GitHub-repo aangemaakt; GitHub CLI geïnstalleerd en `gh auth login` gedaan; uitgavenlimiet voor Actions ingesteld.
- Supabase-project in een EU-regio. Repo-secrets `SUPABASE_HOST` (alleen de host, bijv. `abcd.supabase.co`) en `SUPABASE_PUBLISHABLE_KEY`. Nodig vanaf Task 5.
- De Google OAuth-client en de providerinstellingen in Supabase zijn pas nodig bij TestFlight (UNFORGET S1), niet voor deze fase.

---

### Task 1: Repository, FitlingCore-pakket met enums en grenzen, Linux-CI

**Files:**
- Create: `Packages/FitlingCore/Package.swift`
- Create: `Packages/FitlingCore/Sources/FitlingCore/BodyProfile.swift` (enums + `BodyProfile`)
- Create: `Packages/FitlingCore/Sources/FitlingCore/Limits.swift`
- Create: `Packages/FitlingCore/Tests/FitlingCoreTests/BodyProfileTests.swift`
- Create: `.github/workflows/ci.yml` (job `core`)
- Modify: `.gitignore` (+ `Fitling.xcodeproj/`, `Config/Supabase.xcconfig`, `.build/`, `DerivedData/`, `*.xcresult`)

**Interfaces:**
- Produces:
  - `public enum Sex: String, Sendable, CaseIterable, Codable { case male, female, other }`
  - `public enum ActivityLevel: String, … { case sedentary, light, moderate, active; case veryActive = "very_active"; public var multiplier: Double }`
  - `public enum Goal: String, … { case lose; case buildMuscle = "build_muscle"; case maintain, recomp; public var kcalFactor: Double; public var proteinPerKg: Double }`
  - `public struct BodyProfile: Sendable, Equatable` met `birthDate: Date, sex: Sex, heightCm: Double, weightKg: Double, activityLevel: ActivityLevel, goal: Goal` en een public memberwise init.
  - `public enum Limits` met `static let heightCm: ClosedRange<Double> = 100...250`, `weightKg = 30...350`, `minimumAge = 18`, `earliestBirthDate: DateComponents (1900-01-01)`, `kcal: ClosedRange<Int> = 1...20000`, `proteinG = 0...1000`, `carbsG = 0...5000`, `fatG = 0...2000`.

- [ ] **Step 1: Git en eerste commit.** `git init`, `git branch -M main`, remote = repo van de gebruiker. Commit de bestaande bestanden (CLAUDE.md, PROMPT.md, `.claude/skills`, `docs/` zonder UNFORGET.md, `.gitignore`). Push `main`; maak branch `fase-1`.
- [ ] **Step 2: Schrijf de falende tests** in `BodyProfileTests.swift` (Swift Testing):
  - `rawValuesMatchDatabase`: `Sex.allCases.map(\.rawValue) == ["male","female","other"]`; idem `["sedentary","light","moderate","active","very_active"]` en `["lose","build_muscle","maintain","recomp"]`.
  - `activityMultipliers`: `[1.2, 1.375, 1.55, 1.725, 1.9]` in `allCases`-volgorde.
  - `goalFactors`: `kcalFactor` `[0.80, 1.10, 1.00, 0.95]`, `proteinPerKg` `[2.0, 1.8, 1.6, 2.2]` (volgorde lose, buildMuscle, maintain, recomp).
  - `limitsMatchDatabaseChecks`: elk bereik uit Global Constraints exact.
- [ ] **Step 3: `Package.swift`**: `swift-tools-version: 6.0`, platforms `.iOS(.v17), .macOS(.v14)`, library `FitlingCore`, testTarget `FitlingCoreTests`, geen dependencies.
- [ ] **Step 4: `ci.yml`, job `core`**: `runs-on: ubuntu-latest`, `container: swift:6.2`, `working-directory: Packages/FitlingCore`, `swift test`. Triggers: `push` (alle branches), `pull_request`, `workflow_dispatch`. `concurrency: { group: ci-${{ github.ref }}, cancel-in-progress: true }`.
- [ ] **Step 5: Push naar `fase-1`, controleer rood.** Run: `gh run watch --exit-status` → job `core` faalt op de ontbrekende types.
- [ ] **Step 6: Implementeer** enums, `BodyProfile` en `Limits`.
- [ ] **Step 7: Push, controleer groen.** `gh run watch --exit-status` → `core` slaagt. Bestaat de image `swift:6.2` niet, neem de nieuwste `swift:6.x` op Docker Hub en zet die hier vast.
- [ ] **Step 8: Commit** `feat(core): enums, grenzen en Linux-CI`.

### Task 2: Energieberekening in FitlingCore

**Files:**
- Create: `Packages/FitlingCore/Sources/FitlingCore/NutritionTargets.swift`
- Create: `Packages/FitlingCore/Sources/FitlingCore/EnergyCalculator.swift`
- Test: `Packages/FitlingCore/Tests/FitlingCoreTests/EnergyCalculatorTests.swift`

**Interfaces:**
- Consumes: Task 1-types.
- Produces:
  - `public struct NutritionTargets: Sendable, Equatable, Codable { kcal, proteinG, carbsG, fatG: Int }` + public init.
  - `public struct EnergyCalculation: Sendable, Equatable { bmr: Double; tdee: Double; targets: NutritionTargets; isBelowSafeMinimum: Bool }`
  - `public func age(birthDate: Date, on date: Date, calendar: Calendar) -> Int`
  - `public func calculateEnergy(for profile: BodyProfile, on date: Date, calendar: Calendar) -> EnergyCalculation`
  - `public func safeMinimumKcal(for sex: Sex) -> Int` (male 1500, female/other 1200)
  - `public func isAdult(birthDate: Date, on date: Date, calendar: Calendar) -> Bool` (`age >= Limits.minimumAge`)

Rekenregels (ontwerp §4.7): BMR = `10·kg + 6,25·cm − 5·leeftijd + s` (s: +5 / −161 / −78); TDEE = BMR · `multiplier`; kcal = `(TDEE · kcalFactor / 10).rounded() · 10`; eiwit = `(kg · proteinPerKg).rounded()`; vet = `(kcal · 0,25 / 9).rounded()`; koolhydraten = `max(0, ((kcal − 4·eiwit − 9·vet) / 4).rounded())` op de afgeronde gram-waarden. Afronden met `.rounded()` (half weg van nul).

Leeftijd: niet via `Calendar.dateComponents(.year)` (verschilt per platform rond 29 februari). Neem jaar/maand/dag van beide data in `calendar`; leeftijd = jaarverschil, min 1 als `(maand, dag)` van `date` vóór die van de geboortedatum ligt. Zo is iemand van 29 februari op 1 maart jarig in een niet-schrikkeljaar.

- [ ] **Step 1: Schrijf de falende tests.** Gebruik in alle tests een gregoriaanse kalender met tijdzone UTC en datum 2026-11-18.
  - `manModerateMaintain`: man, 80 kg, 180 cm, geboren 1996-01-10 (30 jr), matig, onderhoud → bmr 1780, tdee 2759, targets `(2760, 128, 389, 77)`, niet onder minimum.
  - `womanLightLose`: vrouw, 65 kg, 165 cm, 1986-05-01 (40), licht, afvallen → bmr 1320,25, targets `(1450, 130, 143, 40)`.
  - `otherSedentaryRecomp`: anders, 70 kg, 175 cm, 2001-02-02 (25), zittend, recomp → bmr 1590,75, targets `(1810, 154, 186, 50)`.
  - `manVeryActiveBuildMuscle`: man, 80 kg, 180 cm, 30 jr, zeer actief, spieropbouw → targets `(3720, 144, 554, 103)`.
  - `belowSafeMinimumWarns`: vrouw, 40 kg, 150 cm, 1951-01-01 (75), zittend, afvallen → kcal 770, `isBelowSafeMinimum == true`.
  - `carbsNeverNegative`: vrouw, 30 kg, 100 cm, 1926-01-01 (100), zittend, recomp → targets `(300, 66, 0, 8)`.
  - `ageAroundBirthday`: geboren 2000-03-15 → 25 op 2026-03-14, 26 op 2026-03-15.
  - `ageLeapDay`: geboren 2008-02-29 → 17 op 2026-02-28, 18 op 2026-03-01; `isAdult` false resp. true.
  - `extremesStayWithinLimits`: voor elke combinatie van gewicht {30, 350}, lengte {100, 250}, leeftijd {18, 120}, elk geslacht, elk activiteitsniveau en elk doel: alle vier targets binnen `Limits`.
- [ ] **Step 2: Push, controleer rood** (`gh run watch --exit-status`, `core` faalt).
- [ ] **Step 3: Implementeer** de functies in `EnergyCalculator.swift` en de structs in `NutritionTargets.swift`.
- [ ] **Step 4: Push, controleer groen.**
- [ ] **Step 5: Commit** `feat(core): BMR, TDEE en macro's`.

### Task 3: Supabase-migratie, RLS en pgTAP-tests

**Files:**
- Create: `supabase/config.toml`
- Create: `supabase/migrations/20261118120000_profiles.sql` (SQL exact uit ontwerp §5.2)
- Create: `supabase/tests/profiles_test.sql`
- Modify: `.github/workflows/ci.yml` (job `backend`)

**Interfaces:**
- Produces: tabel `public.profiles` met kolommen uit ontwerp §5.2; `ProfileRecord` in Task 6 gebruikt exact deze kolomnamen.

- [ ] **Step 1: `config.toml`** met de hand (de CLI draait niet lokaal): `project_id = "fitling"`, `[db] major_version = 17`, `[auth] site_url = "fitling://auth-callback"`, `additional_redirect_urls = ["fitling://auth-callback", "fitling://reset-password"]`, `[auth.email] enable_confirmations = true`, `[functions.delete-account] verify_jwt = false`. Ontbrekende sleutels vallen terug op de standaardwaarden.
- [ ] **Step 2: Schrijf de falende pgTAP-tests** in `profiles_test.sql` (in een transactie, `select plan(n)` … `select * from finish(); rollback;`). Maak twee gebruikers in `auth.users` (id + e-mail). Wissel van gebruiker met `set local role authenticated; set local request.jwt.claims = '{"sub":"<uuid>"}';`.
  - `has_table('public','profiles')` en RLS aan (`select relrowsecurity from pg_class …` is true).
  - A kan een eigen profiel invoegen; A ziet 1 rij; B ziet 0 rijen; B's `update` op A's rij raakt 0 rijen; B kan geen rij met `id` = A invoegen (`throws_ok`).
  - Rol `anon` ziet 0 rijen.
  - Een update met een oudere `updated_at` laat de rij ongewijzigd; met een nieuwere wordt hij bijgewerkt en is `synced_at` veranderd.
  - Een geboortedatum van 17 jaar geleden → `throws_ok` (check-fout); precies 18 jaar geleden → `lives_ok`.
  - `kcal_target = 0` → `throws_ok`; `kcal_target = 20000` → `lives_ok`.
  - `sex = 'x'` → `throws_ok`.
- [ ] **Step 3: Job `backend`** in `ci.yml`: `ubuntu-latest`, `supabase/setup-cli@v1` (vaste CLI-versie), `supabase db start`, `supabase test db`.
- [ ] **Step 4: Push, controleer rood** (de migratie ontbreekt nog → tests falen).
- [ ] **Step 5: Voeg de migratie toe** (exact ontwerp §5.2).
- [ ] **Step 6: Push, controleer groen** op `backend`.
- [ ] **Step 7: Commit** `feat(db): profiles met RLS en sync-regel`.

### Task 4: Edge Function `delete-account`

**Files:**
- Create: `supabase/functions/delete-account/index.ts` (alleen `Deno.serve` met echte dependencies)
- Create: `supabase/functions/delete-account/handler.ts`
- Create: `supabase/functions/delete-account/apple.ts`
- Create: `supabase/functions/delete-account/deno.json` (imports, vaste versie `@supabase/supabase-js@2.x`)
- Test: `supabase/functions/delete-account/handler.test.ts`, `apple.test.ts`
- Modify: `.github/workflows/ci.yml` (job `backend`: `denoland/setup-deno@v2` + `deno test supabase/functions/`)

**Interfaces:**
- Produces (HTTP): `POST /functions/v1/delete-account`, header `Authorization: Bearer <access token>`, body `{ "appleAuthorizationCode"?: string }`. Antwoorden: `200 { "deleted": true }`, `401 { "error": "unauthorized" }`, `400 { "error": "apple_code_required" }` (Apple-account zonder code), `500 { "error": "delete_failed" }`.
- `handler.ts`: `export type Deps = { getUser(token: string): Promise<{ id: string; providers: string[] } | null>; deleteUser(id: string): Promise<void>; revokeApple(code: string): Promise<void>; log(msg: string): void }` en `export async function handle(req: Request, deps: Deps): Promise<Response>`.
- `apple.ts`: `export async function makeClientSecret(cfg: { teamId: string; keyId: string; clientId: string; privateKeyPem: string }, nowSeconds: number): Promise<string>` (ES256-JWT: header `{alg:"ES256",kid}`, claims `iss=teamId, iat=now, exp=now+300, aud="https://appleid.apple.com", sub=clientId`, Web Crypto ECDSA P-256/SHA-256) en `export async function revokeAppleToken(code: string, cfg, fetchFn: typeof fetch, nowSeconds: number): Promise<void>` (POST `https://appleid.apple.com/auth/token` met `grant_type=authorization_code` → `refresh_token`; dan POST `https://appleid.apple.com/auth/revoke` met `token`, `token_type_hint=refresh_token`; beide `application/x-www-form-urlencoded`).

- [ ] **Step 1: Schrijf de falende tests.**
  - `handler.test.ts`: geen header → 401 en `deleteUser` niet aangeroepen; ongeldig token (`getUser` → null) → 401; e-mailaccount → 200, `deleteUser(id)` één keer, `revokeApple` niet; Apple-account met code → `revokeApple(code)` dan `deleteUser`; Apple-account zonder code → 400; `revokeApple` gooit → toch 200 en `deleteUser`, `log` met "apple_revoke_failed"; `deleteUser` gooit → 500.
  - `apple.test.ts`: genereer in de test een P-256-sleutelpaar; `makeClientSecret` → drie base64url-delen, header `alg` = `ES256` en `kid` klopt, claims kloppen, de handtekening verifieert met de publieke sleutel. `revokeAppleToken` met een nep-`fetch`: twee aanroepen naar precies die URL's met de juiste formvelden; een niet-2xx-antwoord gooit een fout.
- [ ] **Step 2: Push, controleer rood** (`backend`).
- [ ] **Step 3: Implementeer** `handler.ts`, `apple.ts` en `index.ts`. `index.ts` haalt het token uit de header, gebruikt een service-client (`createClient(SUPABASE_URL, <service-sleutel>)`), `auth.getUser(token)`, `auth.admin.deleteUser(id)`, en `app_metadata.providers` voor `providers`. Controleer de naam van de service-sleutel-omgevingsvariabele in de Supabase-docs (ontwerp §8).
- [ ] **Step 4: Push, controleer groen.**
- [ ] **Step 5: Commit** `feat(functions): delete-account met Apple-tokenintrekking`.

### Task 5: Xcode-project, vormgeving, String Catalog, stringcheck en macOS-CI

**Files:**
- Create: `project.yml`, `Config/Shared.xcconfig`
- Create: `Fitling/App/FitlingApp.swift`, `Fitling/App/AppConfiguration.swift`
- Create: `Fitling/DesignSystem/Spacing.swift`, `Fitling/Resources/Assets.xcassets` (named colors licht/donker; het app-icoon hoort bij TestFlight, UNFORGET S1), `Fitling/Resources/Localizable.xcstrings`, `Fitling/Resources/Fitling.entitlements`, `Fitling/Info.plist` (via XcodeGen)
- Create: `DESIGN.md` (via de `impeccable`-skill)
- Create: `scripts/check-strings.mjs`, `scripts/check-strings.test.mjs`
- Create: `FitlingUITests/LaunchTests.swift`
- Modify: `.github/workflows/ci.yml` (jobs `strings`, `ios`)

**Interfaces:**
- Produces:
  - `struct AppConfiguration { let supabaseURL: URL; let publishableKey: String; static func fromBundle(_ bundle: Bundle = .main) throws -> AppConfiguration }`. Leest de Info.plist-sleutels `SupabaseHost` en `SupabasePublishableKey` (gevuld met `$(SUPABASE_HOST)` en `$(SUPABASE_PUBLISHABLE_KEY)`); URL = `https://` + host.
  - `enum Spacing { static let xs: CGFloat = 4, s = 8, m = 12, l = 16, xl = 24, xxl = 32 }`
  - Named colors, met Swift-symbolen uit de asset catalog (`ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES`). De namen komen uit DESIGN.md.
  - Targets: `Fitling` (app), `FitlingTests` (unit, host = app), `FitlingUITests`. Scheme `Fitling` test beide.
  - URL-scheme `fitling`; entitlement `com.apple.developer.applesignin = [Default]`; bundle id `nl.fitling.Fitling` in `Shared.xcconfig` (wordt definitief bij TestFlight, UNFORGET S1).
- Stringcheck-regels: sleutels zijn string literals die beginnen met een prefix uit Global Constraints. Elke sleutel in `Fitling/**/*.swift` (behalve `Fitling/UITesting/`) moet in de catalog staan met `nl`, `en` en `de` in staat `translated` (stringUnit of variations). Een literal met `\(…)` matcht een catalogsleutel waarin op die plek een formaatteken staat (`%@`, `%lld`, `%ld`, `%d`, `%f`, `%.Nf`). Fout: een `Text(`, `Button(`, `Label(`, `.navigationTitle(`, `String(localized:` of `.accessibilityLabel(` met een literal zonder geldig prefix. Waarschuwing (geen fout): sleutels in de catalog die nergens worden gebruikt. Exitcode 1 bij een fout.

- [ ] **Step 1: Vormgeving.** Roep de `impeccable`-skill aan voor een DESIGN.md: palet (licht/donker, contrast AA), typografie (Dynamic Type-stijlen), spacing en de toon van de teksten, binnen de regels uit Global Constraints. Leg de kleurnamen vast.
- [ ] **Step 2: Falende node-tests** (`node --test scripts/check-strings.test.mjs`, met tijdelijke mappen als fixtures): ontbrekende `de` → fout; `Text("Hallo wereld")` → fout; `Text("auth.signIn.title")` aanwezig in alle talen → ok; `Text("targets.kcal \(kcal)")` met catalogsleutel `targets.kcal %lld` → ok; ongebruikte sleutel → alleen waarschuwing; `Fitling/UITesting/` wordt overgeslagen.
- [ ] **Step 3: Draai lokaal, controleer rood:** `node --test scripts/check-strings.test.mjs` → FAIL.
- [ ] **Step 4: Implementeer `check-strings.mjs`** (alleen Node-builtins).
- [ ] **Step 5: Draai lokaal, controleer groen:** `node --test scripts/check-strings.test.mjs` → PASS.
- [ ] **Step 6: Projectbestanden.** `project.yml`: `options.developmentLanguage: nl`, `deploymentTarget iOS 17.0`, `packages`: `FitlingCore` (path) en `Supabase` (url `https://github.com/supabase/supabase-swift`, `exactVersion`: de nieuwste 2.x-release volgens `gh api repos/supabase/supabase-swift/releases/latest`). `configFiles` naar `Config/Shared.xcconfig`, dat met `#include? "Supabase.xcconfig"` de secrets laadt. `FitlingApp` toont in deze taak het laadscherm van `RootView` (Task 11 vult de rest in). De catalog bevat in deze taak alleen de sleutels die al gebruikt worden.
- [ ] **Step 7: Falende UI-test** `LaunchTests.testAppLaunches`: de app start en het laadscherm (accessibility identifier `root.loading`) bestaat binnen 5 s.
- [ ] **Step 8: CI-jobs.** `strings`: ubuntu, `node scripts/check-strings.mjs` + `node --test scripts/`. `ios`: `macos-15` (of nieuwer, zie ontwerp §8), alleen op `push` naar `main` en `workflow_dispatch`, `needs: [core, strings]`, `timeout-minutes: 30`. Stappen: checkout, `brew install xcodegen`, `Config/Supabase.xcconfig` schrijven uit de secrets, cache van `~/Library/Caches/org.swift.swiftpm` + `SourcePackages` met als sleutel de hash van `project.yml`, `xcodegen generate`, `xcodebuild test -scheme Fitling -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -resultBundlePath TestResults.xcresult CODE_SIGNING_ALLOWED=NO`, en het `.xcresult` als artefact uploaden (`if: always()`). Zet de beschikbare Xcode-versie en simulator vast na een eerste run met `xcodebuild -showsdks` en `xcrun simctl list devices`.
- [ ] **Step 9: Push en start de macOS-job:** `gh workflow run ci.yml --ref fase-1`, dan `gh run watch --exit-status` → `ios` groen, `strings` groen.
- [ ] **Step 10: Commit** `feat(app): projectopzet, vormgeving, String Catalog en macOS-CI`.

### Task 6: SwiftData-schema, ProfileRecord en geboortedatumkalender

**Files:**
- Create: `Fitling/Data/Schema/FitlingSchemaV1.swift`, `Fitling/Data/Schema/FitlingMigrationPlan.swift`
- Create: `Fitling/Data/ProfileRecord.swift`, `Fitling/Data/BirthDateCalendar.swift`
- Test: `FitlingTests/ProfileRecordTests.swift`, `FitlingTests/BirthDateCalendarTests.swift`

**Interfaces:**
- Consumes: `BodyProfile`, `NutritionTargets`, enums (Task 1–2).
- Produces:
  - `FitlingSchemaV1.UserProfile` (`@Model`, velden exact ontwerp §5.4) + `typealias UserProfile`; computed `sex`, `activityLevel`, `goal`, `bodyProfile: BodyProfile` en `targets: NutritionTargets` (get/set); `init(id: UUID, healthConsentAt: Date, healthConsentVersion: Int, body: BodyProfile, targets: NutritionTargets, targetsAreManual: Bool, updatedAt: Date)` met `needsPush = true`.
  - `FitlingMigrationPlan` (ontwerp §5.4); `func makeModelContainer(inMemory: Bool) throws -> ModelContainer` in `FitlingSchemaV1.swift`.
  - `enum BirthDateCalendar { static let calendar: Calendar /* gregoriaans, UTC */; static func string(from date: Date) -> String /* yyyy-MM-dd */; static func date(from string: String) -> Date? }`
  - `struct ProfileRecord: Codable, Equatable, Sendable` met eigenschappen in camelCase en `CodingKeys` naar exact de SQL-kolommen; `birthDate: String`, `heightCm`/`weightKg: Double`, `updatedAt`/`healthConsentAt: Date`, `syncedAt: Date?` (alleen decode). `init(_ profile: UserProfile)` en `func apply(to profile: UserProfile)` (zet `needsPush = false`).

- [ ] **Step 1: Falende tests.**
  - `ProfileRecordTests.encodesSnakeCaseKeys`: `JSONEncoder` op een record → JSON-sleutels exact `id, health_consent_at, health_consent_version, birth_date, sex, height_cm, weight_kg, activity_level, goal, kcal_target, protein_target_g, carbs_target_g, fat_target_g, targets_are_manual, updated_at`; `synced_at` wordt niet meegestuurd.
  - `roundTripsThroughUserProfile`: UserProfile → record → nieuwe UserProfile (in-memory container) → alle velden gelijk; `apply` zet `needsPush` op false.
  - `BirthDateCalendarTests.stableAcrossTimeZones` (**Review Focus 1**): met `NSTimeZone.default` op `America/Los_Angeles` en daarna op `Pacific/Auckland` blijft `string(from: date(from: "2000-03-15")!) == "2000-03-15"`, en is `age(birthDate:on:calendar: BirthDateCalendar.calendar)` op 2026-03-15 UTC gelijk aan 26. Zet de standaardtijdzone na de test terug.
  - `rejectsInvalidStrings`: `date(from: "2000-02-30") == nil`, `date(from: "15-03-2000") == nil`.
- [ ] **Step 2: Push + `gh workflow run ci.yml --ref fase-1`, controleer rood** (`ios`).
- [ ] **Step 3: Implementeer** de vier bestanden.
- [ ] **Step 4: Push + macOS-run, controleer groen.**
- [ ] **Step 5: Commit** `feat(data): SwiftData-schema V1 en profielmapping`.

### Task 7: Auth-laag: AuthProviding, AuthService, AppleSignIn en nep-auth

**Files:**
- Create: `Fitling/Services/AuthProviding.swift`, `Fitling/Services/AuthService.swift`, `Fitling/Services/AppleSignIn.swift`
- Create: `Fitling/UITesting/FakeAuthProvider.swift` (`#if DEBUG`)
- Test: `FitlingTests/AppleSignInTests.swift`, `FitlingTests/AuthErrorMappingTests.swift`

**Interfaces:**
- Produces:
  - `enum AuthState: Equatable, Sendable { case loading, signedOut, awaitingEmailVerification(email: String), signedIn(userID: UUID, usesApple: Bool) }`
  - `enum AuthLink: Equatable { case signedIn, passwordRecovery }`
  - `enum AuthError: Error, Equatable { case invalidCredentials, emailNotConfirmed, weakPassword, rateLimited, network, invalidOrForeignLink, server }`
  - `@MainActor protocol AuthProviding: AnyObject { var state: AuthState { get }; func signInWithApple(idToken: String, nonce: String) async throws(AuthError); func signInWithGoogle() async throws(AuthError); func signUp(email: String, password: String) async throws(AuthError); func signIn(email: String, password: String) async throws(AuthError); func resendVerification(email: String) async throws(AuthError); func requestPasswordReset(email: String) async throws(AuthError); func handle(url: URL) async throws(AuthError) -> AuthLink; func updatePassword(_ password: String) async throws(AuthError); func deleteAccount(appleAuthorizationCode: String?) async throws(AuthError); func signOut() async throws(AuthError) }`
  - `@Observable @MainActor final class AuthService: AuthProviding` met `init(client: SupabaseClient)`. Luistert naar `client.auth.authStateChanges`; redirect-URL's `fitling://auth-callback` (signUp, Google) en `fitling://reset-password` (reset); `deleteAccount` roept `client.functions.invoke("delete-account", …)` aan en logt daarna lokaal uit.
  - `func makeSupabaseClient(_ config: AppConfiguration) -> SupabaseClient` met `emitLocalSessionAsInitialSession: true` (ontwerp §4.1).
  - `static func mapAuthError(_ error: Error) -> AuthError` op `AuthService`: URLError → `.network`; HTTP 429 → `.rateLimited`; "invalid login credentials" → `.invalidCredentials`; "email not confirmed" → `.emailNotConfirmed`; zwak wachtwoord → `.weakPassword`; overige → `.server`.
  - `enum AppleSignIn { static func makeNonce(length: Int = 32) -> String; static func sha256(_ input: String) -> String /* hex, lowercase */; @MainActor static func requestCredential(hashedNonce: String) async throws -> (idToken: String, authorizationCode: String) }`
  - `@Observable @MainActor final class FakeAuthProvider: AuthProviding` (DEBUG): instelbare `state`, per methode een `nextError: AuthError?`, en tellers `calls: [String: Int]`.

- [ ] **Step 1: Falende tests.**
  - `AppleSignInTests.sha256KnownVector`: `sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"`.
  - `nonceLengthAndCharset`: 32 tekens uit `0-9A-Za-z-._`; twee aanroepen verschillen.
  - `AuthErrorMappingTests`: `URLError(.notConnectedToInternet)` → `.network`; een fout met HTTP-status 429 → `.rateLimited`. Controleer de foutvorm van supabase-swift 2.x (`AuthError.api(message:errorCode:…)`) in de vastgezette versie en schrijf de overige mappingtests op die echte vorm.
- [ ] **Step 2: Push + macOS-run, controleer rood.**
- [ ] **Step 3: Implementeer** de bestanden. Controleer de handtekeningen in ontwerp §8 tegen de bron van de vastgezette supabase-swift-versie (`.build/checkouts` op CI of de tag op GitHub) en gebruik precies die.
- [ ] **Step 4: Push + macOS-run, controleer groen.**
- [ ] **Step 5: Commit** `feat(auth): AuthService, Apple-nonce en nep-auth voor tests`.

### Task 8: Auth-schermen en ViewModels

**Files:**
- Create in `Fitling/Features/Auth/`: `WelcomeView.swift`, `EmailAuthView.swift` + `EmailAuthViewModel.swift` (registreren/inloggen), `VerifyEmailView.swift` + `VerifyEmailViewModel.swift`, `ForgotPasswordView.swift` + `ForgotPasswordViewModel.swift`, `ResetPasswordView.swift` + `ResetPasswordViewModel.swift`
- Modify: `Fitling/Resources/Localizable.xcstrings`
- Test: `FitlingTests/EmailAuthViewModelTests.swift`, `ForgotPasswordViewModelTests.swift`, `ResetPasswordViewModelTests.swift`

**Interfaces:**
- Consumes: `AuthProviding`, `AuthError`, `FakeAuthProvider` (Task 7).
- Produces:
  - Elk ViewModel: `@Observable @MainActor final class`, `init(auth: any AuthProviding)`, `private(set) var isWorking: Bool`, `private(set) var messageKey: String?` (een catalogsleutel; de view toont `Text(LocalizedStringKey(messageKey))`).
  - `VerifyEmailViewModel`: `init(auth:email:)`, `func resend() async` → `resendVerification(email:)`; na succes `messageKey = "auth.verify.resent"`.
  - `EmailAuthViewModel`: `enum Mode { case signUp, signIn }`; `var email, password: String`; `func submit() async`. Na een signUp (ook bij een al bekend adres) wordt de status `awaitingEmailVerification`. Bij `.emailNotConfirmed` toont `signIn` het verificatiescherm.
  - `ForgotPasswordViewModel`: `func submit() async`. Bij succes en bij elke serverfout behalve `.rateLimited`/`.network` dezelfde neutrale melding `auth.reset.sent` ("Als er een account met dit adres is, krijg je een mail. Log je in met Apple of Google? Gebruik dan die knop."); `.rateLimited` → `auth.reset.rateLimited`; `.network` → `error.network`.
  - `ResetPasswordViewModel`: `func submit() async` → `updatePassword`; `.invalidOrForeignLink` → `auth.reset.linkInvalid`.
  - `WelcomeView`: knoppen Apple (`SignInWithAppleButton` + `AppleSignIn`), Google en E-mail; accessibility identifiers `welcome.apple`, `welcome.google`, `welcome.email`.

- [ ] **Step 1: Falende tests** (met `FakeAuthProvider`).
  - `signUpCallsAuthOnce` (**Review Focus 3**): `submit()` twee keer direct na elkaar (`async let`) → `calls["signUp"] == 1`.
  - `signInEmailNotConfirmedShowsVerification`: `nextError = .emailNotConfirmed` → fake-state wordt `awaitingEmailVerification(email:)`.
  - `invalidCredentialsShowsMessage`: → `messageKey == "auth.error.invalidCredentials"`.
  - `verifyEmailResendOnce`: `resend()` twee keer direct na elkaar → `calls["resendVerification"] == 1`, `messageKey == "auth.verify.resent"`.
  - `forgotPasswordNeutralOnSuccess` en `forgotPasswordNeutralOnServerError` (`.server`) → beide `messageKey == "auth.reset.sent"`; `.rateLimited` → `"auth.reset.rateLimited"`; dubbel tikken → `calls["requestPasswordReset"] == 1`.
  - `resetPasswordForeignLink`: `.invalidOrForeignLink` → `messageKey == "auth.reset.linkInvalid"`.
- [ ] **Step 2: Push + macOS-run, controleer rood.**
- [ ] **Step 3: Implementeer** de ViewModels en views, plus de teksten in nl/en/de (kort en menselijk, geen uitroeptekens; Duits niet letterlijk vertaald). Draai lokaal `node scripts/check-strings.mjs` → exit 0.
- [ ] **Step 4: Push + macOS-run, controleer groen.**
- [ ] **Step 5: Commit** `feat(auth): schermen voor inloggen, registreren en wachtwoord`.

### Task 9: ProfileSync

**Files:**
- Create: `Fitling/Data/ProfileSync.swift`
- Test: `FitlingTests/ProfileSyncTests.swift`

**Interfaces:**
- Consumes: `UserProfile`, `ProfileRecord` (Task 6).
- Produces:
  - `enum PullOutcome: Equatable { case remoteMissing, adoptedRemote, keptLocal, unchanged }`
  - `enum SyncError: Error, Equatable { case network, rejected(String) }`
  - `@Observable @MainActor final class ProfileSync` met `init(context: ModelContext, fetchRemote: @escaping @Sendable (UUID) async throws -> ProfileRecord?, upsertRemote: @escaping @Sendable (ProfileRecord) async throws -> Void)`; `func pull(userID: UUID) async throws(SyncError) -> PullOutcome`; `func push(userID: UUID) async throws(SyncError)`; `func localProfile(userID: UUID) -> UserProfile?`; `func deleteLocalData() throws`; `private(set) var lastRejection: String?`.
  - `static func live(client: SupabaseClient, context: ModelContext) -> ProfileSync`: `fetchRemote` = `client.from("profiles").select().eq("id", value:).limit(1)`, `upsertRemote` = `client.from("profiles").upsert(record)`.
  - Regels (ontwerp §4.5). Pull: geen lokaal profiel + remote → adopteren; geen remote → `remoteMissing`; lokaal `needsPush` → `keptLocal`; `remote.updatedAt > local.updatedAt` → adopteren; anders `unchanged`. Push: alleen als `needsPush`. Wis `needsPush` alleen als `updatedAt` nog gelijk is aan de verstuurde waarde. URLError → `.network`; elke andere fout → `.rejected`, met `lastRejection` gezet en `needsPush` behouden. Geen eigen herhaallus; opnieuw proberen gebeurt alleen bij de triggers in Task 11.

- [ ] **Step 1: Falende tests** (in-memory container, closures die bijhouden hoe vaak ze zijn aangeroepen).
  - `pullAdoptsRemoteWhenNoLocal`, `pullReportsRemoteMissing`, `pullKeepsLocalWithPendingPush`, `pullAdoptsNewerRemote`, `pullIgnoresOlderRemote`.
  - `pullNetworkErrorThrowsNetwork`: fetch gooit `URLError(.notConnectedToInternet)` → `.network`.
  - `pushClearsFlagWhenUnchanged`.
  - `pushKeepsFlagWhenEditedDuringPush`: de upsert-closure wijzigt tijdens het verzenden `updatedAt` van het lokale profiel → `needsPush` blijft true.
  - `pushRejectedKeepsFlagAndReports` (**Review Focus 4**): upsert gooit een niet-netwerkfout → `.rejected`, `lastRejection != nil`, `needsPush == true`, upsert precies één keer aangeroepen.
  - `pushSkipsWhenNothingPending`: upsert 0 keer aangeroepen.
- [ ] **Step 2: Push + macOS-run, controleer rood.**
- [ ] **Step 3: Implementeer** `ProfileSync`.
- [ ] **Step 4: Push + macOS-run, controleer groen.**
- [ ] **Step 5: Commit** `feat(sync): offline-first profielsync`.

### Task 10: Onboarding

**Files:**
- Create in `Fitling/Features/Onboarding/`: `HealthConsent.swift`, `OnboardingViewModel.swift`, `OnboardingFlowView.swift`, één view per stap (`ConsentStepView`, `BirthDateStepView`, `SexStepView`, `HeightStepView`, `WeightStepView`, `ActivityStepView`, `GoalStepView`, `ResultStepView`, `UnderageView`)
- Modify: `Localizable.xcstrings`
- Test: `FitlingTests/OnboardingViewModelTests.swift`

**Interfaces:**
- Consumes: `calculateEnergy`, `isAdult`, `Limits` (Task 1–2), `UserProfile`, `BirthDateCalendar` (Task 6).
- Produces:
  - `enum HealthConsent { static let currentVersion = 1 }`
  - `@Observable @MainActor final class OnboardingViewModel` met `init(userID: UUID, context: ModelContext, locale: Locale, now: @escaping () -> Date)`; `enum Step: Int, CaseIterable { case consent, birthDate, sex, height, weight, activity, goal, result }`; `private(set) var step: Step`; `var consentGiven: Bool`; `var birthDate: Date`; `var sex: Sex?`; `var activityLevel: ActivityLevel?`; `var goal: Goal?`; `var heightInput: Measurement<UnitLength>`; `var weightInput: Measurement<UnitMass>` (in de eenheid van `locale`); `var canContinue: Bool`; `var isUnderage: Bool`; `var calculation: EnergyCalculation?`; `func next()`; `func back()`; `func finish() throws -> UserProfile` (slaat op met `healthConsentAt = now()`, `healthConsentVersion = HealthConsent.currentVersion`, `targetsAreManual = false`, `needsPush = true`).
  - `canContinue`: consent → `consentGiven`; birthDate → volwassen volgens `BirthDateCalendar.calendar`; lengte/gewicht → omgerekend naar cm/kg binnen `Limits`; sex/activity/goal → niet nil.
  - Bij een geboortedatum onder de 18 is `isUnderage` true, blokkeert `next()`, en toont de flow `UnderageView(onDeleteAccount: @escaping () async -> Void)`, met de knop "Account verwijderen". Task 11 koppelt die closure aan `AccountViewModel.deleteAccount`.
  - `OnboardingFlowView(viewModel:onFinished: @escaping (UserProfile) async -> Void)`; de flow roept `onFinished` aan na een geslaagde `finish()`.

- [ ] **Step 1: Falende tests.**
  - `cannotPassConsentWithoutAgreeing`.
  - `underageBlocksAndFlags`: geboren 2009-01-01, `now` = 2026-11-18 → `isUnderage`, `canContinue == false`.
  - `exactlyEighteenPasses`: geboren 2008-11-18 → door.
  - `imperialInputStoredMetric` (**Review Focus 2**): `locale` `en_US`, `weightInput = 176 lb`, `heightInput = 70 in` → na `finish()`: `weightKg` ≈ 79,8 (±0,05), `heightCm` ≈ 177,8 (±0,05).
  - `outOfRangeWeightBlocks`: 20 kg → `canContinue == false`.
  - `finishStoresConsentAndTargets`: volledige flow (man, 80 kg, 180 cm, 30 jr, matig, onderhoud) → opgeslagen profiel met targets `(2760, 128, 389, 77)`, `healthConsentVersion == 1`, `needsPush == true`.
- [ ] **Step 2: Push + macOS-run, controleer rood.**
- [ ] **Step 3: Implementeer** het ViewModel en de views. Stappen staan in een `ScrollView`, zodat "Verder" ook bij de grootste tekst bereikbaar blijft; identifiers `onboarding.continue`, `onboarding.step.<naam>`. De `DatePicker` krijgt `.environment(\.calendar, BirthDateCalendar.calendar)` en `.environment(\.timeZone, .gmt)`. Teksten in nl/en/de; `check-strings` lokaal groen.
- [ ] **Step 4: Push + macOS-run, controleer groen.**
- [ ] **Step 5: Commit** `feat(onboarding): toestemming, 18+ en doelberekening`.

### Task 11: Dagdoel, profiel en account, routering en sync-triggers

**Files:**
- Create in `Fitling/Features/Profile/`: `ProfileView.swift`, `EditProfileView.swift`, `EditTargetsView.swift`, `ProfileViewModel.swift`
- Create in `Fitling/Features/Account/`: `AccountView.swift`, `AccountViewModel.swift`
- Create: `Fitling/App/RootView.swift` (volledig), `Fitling/App/RootViewModel.swift`, `Fitling/App/NeedsConnectionView.swift`
- Modify: `Fitling/App/FitlingApp.swift` (echte wiring, `.onOpenURL`, sync-triggers), `Localizable.xcstrings`
- Test: `FitlingTests/RootViewModelTests.swift`, `ProfileViewModelTests.swift`, `AccountViewModelTests.swift`

**Interfaces:**
- Consumes: alles uit Task 6–10.
- Produces:
  - `@Observable @MainActor final class RootViewModel` met `init(auth: any AuthProviding, sync: ProfileSync)`; `enum Screen: Equatable { case loading, welcome, verifyEmail(String), needsConnection, onboarding(UUID), home(UUID) }`; `private(set) var screen: Screen`; `func refresh() async`; `func open(_ url: URL) async`; `func onboardingFinished(_ profile: UserProfile) async` (scherm → home, daarna `sync.push`). Een URL die binnenkomt terwijl `auth.state == .loading` wordt bewaard en verwerkt zodra de status bekend is.
  - Routering: `signedOut` → welcome; `awaitingEmailVerification(e)` → verifyEmail(e); `signedIn(id)`: lokaal profiel → home (met pull op de achtergrond); geen lokaal profiel → `pull`: `remoteMissing` → onboarding, `adoptedRemote` → home, `.network` → needsConnection. `AuthLink.passwordRecovery` → ResetPasswordView als sheet.
  - `@Observable @MainActor final class ProfileViewModel` met `init(profile: UserProfile, sync: ProfileSync, now: @escaping () -> Date)`; `var calculation: EnergyCalculation`; `enum SaveResult { case saved, askRecalculate }`; `func saveProfile(_ body: BodyProfile) -> SaveResult` (`askRecalculate` alleen als `targetsAreManual`); `func recalculateTargets()`; `enum TargetsError: Error, Equatable { case outOfRange(field: String) }`; `func saveTargets(_ t: NutritionTargets) throws(TargetsError)` (zet `targetsAreManual = true`). Elke wijziging: `updatedAt = now()`, `needsPush = true`, en na 2 s een push (ontwerp §4.5).
  - `@Observable @MainActor final class AccountViewModel` met `init(auth: any AuthProviding, sync: ProfileSync, userID: UUID, usesApple: Bool, appleCode: @escaping () async throws -> String)`; `enum SignOutResult { case signedOut, unsyncedChanges }`; `func signOut(force: Bool) async -> SignOutResult`; `func deleteAccount() async`; `private(set) var isWorking`.
  - Sync-triggers in `FitlingApp`: bij app-start, bij `scenePhase == .active`, en bij `NWPathMonitor` → `.satisfied`: `sync.push` en daarna `sync.pull`.

- [ ] **Step 1: Falende tests.**
  - `RootViewModelTests`: `signedOutShowsWelcome`; `verificationShowsVerifyScreen`; `firstDeviceOnlineNoRemoteGoesToOnboarding`; `firstDeviceOnlineWithRemoteGoesHome` (profiel lokaal aangemaakt); `firstDeviceOfflineShowsNeedsConnection` (fetch gooit URLError; er wordt geen profiel aangemaakt); `existingLocalProfileGoesHomeWithoutWaiting`; `urlBeforeAuthReadyIsHandledAfterwards`; `onboardingFinishedGoesHomeAndPushes` (upsert één keer aangeroepen).
  - `ProfileViewModelTests`: `editingProfileRecalculatesAutoTargets`; `editingProfileWithManualTargetsAsks`; `saveTargetsOutOfRangeThrows` (kcal 0 → `.outOfRange(field: "kcal")`); `saveTargetsMarksManualAndPending`.
  - `AccountViewModelTests`: `signOutOfflineWithPendingWarns` (push gooit `.network`, `needsPush` → `.unsyncedChanges`, `signOut` niet aangeroepen); `signOutForceWipesLocal`; `deleteAccountAppleSendsCode`; `deleteAccountEmailSendsNil`; `deleteAccountDoubleTapCallsOnce` (**Review Focus 3**); `deleteAccountWipesLocalData`.
- [ ] **Step 2: Push + macOS-run, controleer rood.**
- [ ] **Step 3: Implementeer.** `ProfileView` toont kcal, eiwit, koolhydraten en vet, met uitleg over BMR, TDEE, activiteitsfactor en doelfactor, en de waarschuwing als `isBelowSafeMinimum`. `EditTargetsView` gebruikt `Limits`. `AccountView` heeft een bevestiging voor verwijderen. Getallen worden opgemaakt via `Measurement` en `Locale` (kcal/kJ, kg/lb). Teksten in nl/en/de; `check-strings` lokaal groen.
- [ ] **Step 4: Push + macOS-run, controleer groen.**
- [ ] **Step 5: Commit** `feat(app): dagdoel, profiel, account en routering`.

### Task 12: UI-flowtest met screenshots en afronding

**Files:**
- Create: `Fitling/UITesting/UITestEnvironment.swift` (`#if DEBUG`)
- Create: `FitlingUITests/OnboardingFlowTests.swift`
- Modify: `Fitling/App/FitlingApp.swift` (in DEBUG bij `--ui-testing`: `FakeAuthProvider` + in-memory container + een `ProfileSync` met closures die geen profiel teruggeven en elke upsert accepteren)
- Modify: `.github/workflows/ci.yml` (screenshots exporteren als artefact)
- Modify: `docs/UNFORGET.md` (alleen als er tijdens de bouw iets is uitgesteld)

**Interfaces:**
- Consumes: `FakeAuthProvider` (Task 7), `RootViewModel` (Task 11).
- Produces: startargumenten `--ui-testing` (ingelogd, geen profiel) en `--ui-testing-signed-out` (uitgelogd).

- [ ] **Step 1: Falende UI-tests.**
  - `testWelcomeScreen` (`--ui-testing-signed-out`): `welcome.apple`, `welcome.google`, `welcome.email` bestaan; screenshot "welkom".
  - `testOnboardingToTargets` (`--ui-testing`): doorloop alle stappen (akkoord, geboortedatum 30 jaar terug, man, 180 cm, 80 kg, matig, onderhoud) → dagdoel toont "2760"; na elke stap een screenshot (`XCTAttachment`, `lifetime = .keepAlways`).
  - `testOnboardingDarkMode`: hetzelfde begin in donkere modus (`XCUIDevice.shared.appearance = .dark` vóór de start, na afloop terug op `.light`), screenshot van de eerste twee stappen.
  - `testLargestTextKeepsContinueReachable` (**Review Focus 5**): startargument `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`; in elke stap is `onboarding.continue` `isHittable` (eventueel na `swipeUp()`).
- [ ] **Step 2: Push + macOS-run, controleer rood.**
- [ ] **Step 3: Implementeer** `UITestEnvironment` en de wiring in `FitlingApp`.
- [ ] **Step 4: Screenshots exporteren.** CI-stap na de tests: `xcrun xcresulttool export attachments --path TestResults.xcresult --output-path screenshots` (Xcode 16+; bestaat het subcommando niet in de runner-versie, gebruik dan `xcresulttool get` volgens `xcrun xcresulttool help`), en `screenshots/` uploaden als artefact.
- [ ] **Step 5: Push + macOS-run, controleer groen.** Download de screenshots (`gh run download -n screenshots`) en bekijk ze. Controleer tegen DESIGN.md: geen afgekapte teksten, contrast in donkere modus, consistente spacing.
- [ ] **Step 6: Merge `fase-1` naar `main`** (na akkoord van de gebruiker) → volledige CI op `main`, alle vier de jobs groen.
- [ ] **Step 7: UNFORGET bijwerken.** Draai `PYTHONIOENCODING=utf-8 python .claude/skills/unforget/scripts/verify_ledger.py --file docs/UNFORGET.md --dir docs` → `gate_pass: true`. Zet tijdens de bouw uitgestelde punten erin via `/unforget add`.
- [ ] **Step 8: Commit** `test(ui): onboardingflow met screenshots`.

---

## Na elke bugfix

Draai `bug-echo` op de fix (CLAUDE.md) voordat de taak als klaar geldt.

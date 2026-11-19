# Fitling – taken voor Opus 5.5

Het fundament staat op `main`: rekenregels (`Packages/FitlingCore`), database (`supabase/schema.sql`), lokale modellen (`Fitling/Core/Models`) en de beslissingen (`docs/ARCHITECTURE.md`). **Werk verder op branch `fase-1-opbouw`**: daar staan bovenop `main` ook inloggen als service (1.2), de sync (1.3) en twee verbeteringen van het fundament (`SyncRules.pullStart`, `SyncCursor.pulledAt`). Die branch gaat aan het eind van fase 1 in één keer naar `main`, na akkoord van de gebruiker. Dit bestand zegt wat er gebouwd wordt, in welke volgorde, en wanneer een taak af is. De ontwerpbeslissingen zijn genomen; staat er toch iets open, dan staat dat bij de taak.

## Lees eerst

1. `CLAUDE.md` (projectregels), `PROMPT.md` (wat de app moet doen), `docs/ARCHITECTURE.md` (hoe), `docs/RISKS.md` (wat mis kan gaan).
2. De skills uit `CLAUDE.md` gelden voor elke taak.

## Werkafspraken

- **Geen Mac.** Bouwen en testen gebeurt in GitHub Actions. De Mac-job draait alleen als het commitbericht `[ios]` bevat. Er zijn ongeveer 190 Mac-minuten per maand; een run kost er ongeveer vijf. Bundel het werk van een taak in zo weinig mogelijk `[ios]`-commits en lees je Swift na vóór je pusht.
- **Geen getypeerde fout op een generieke async-eis van een protocol.** `func f<T>(...) async throws(E)` als protocol-eis laat de compiler van Xcode 16.4 (Swift 6.1.2) crashen, zonder foutregel in het log (zoek dan op `Stack dump` in `xcodebuild.log` uit het artefact `TestResults`). Gewone `throws` gebruiken en het fouttype in commentaar noemen, zoals in `RemoteStore`.
- **Wat op Linux kan, hoort in FitlingCore.** Pure logica met tests daar; dat is gratis en snel.
- **Eerst de test, dan de code**, en zie de test falen. Testnamen beschrijven gedrag (`returnsTiredWhenSevenDayAverageIsThirtyPercentUnderTarget`).
- **Naslag.** De eerdere fase 1 werkte en was getest (88 tests). Neem over wat past: `git show origin/fase-1:<pad>`. Overnemen en aanpassen is beter dan opnieuw schrijven. Het herontwerp "Verzamelfiguren" staat op GitHub: `git show origin/herontwerp-verzamelfiguren:<pad>`.
- **Schema wijzigen** kan zolang er geen productiedatabase is (ARCHITECTURE D-07): pas `supabase/schema.sql`, het model in `Fitling/Core/Models`, zo nodig `scripts/check-models.mjs` en een pgTAP-test aan in dezelfde commit.
- **Partner, niet wezentje.** In alles wat de gebruiker leest (app, meldingen, widget) heet hij "je partner". In de code blijft `Creature` staan.
- **Teksten** altijd via `Localizable.xcstrings`, in nl, en en de. De catalogus bevat al de teksten van de eerdere fase 1; hergebruik de sleutels.
- **Klaar** is: gebouwd, tests groen in CI, en bij schermen een screenshot naar de gebruiker (die wil tussendoor meekijken).
- **Vraag de gebruiker** vóór een merge naar `main`, vóór iets op het echte Supabase-project, en vóór een download van materiaal van derden.

## Terug naar Fable

Stop en meld het, in plaats van zelf te beslissen, bij:

- een sync-fout die je na één gerichte poging niet begrijpt (verloren of dubbele rijen, rijen die blijven terugkomen);
- een wens om een regel of constante in `FitlingCore` te veranderen (drempels van de partner, XP, progressie, ondergrens);
- een wijziging in de betekenis van het schema (wie mag wat zien, hoe conflicten worden opgelost);
- de taken die hieronder met **→ Fable** zijn gemarkeerd.

Hoe: `/model fable` en de taak noemen.

## Vóór fase 1 (met de gebruiker)

| Nr | Wat | Wie |
|---|---|---|
| 0.1 | Gedaan op 2026-11-19: `fundament` staat op `main` (pull request 1, alle CI-jobs groen). | – |
| 0.2 | Het ontwikkelproject in Supabase heeft mogelijk nog de oude tabel `profiles`. Er zijn geen echte gebruikers. Na akkoord van de gebruiker: de oude tabel en `private.apply_sync_rules` verwijderen en `supabase/schema.sql` uitvoeren (SQL-editor of `psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/schema.sql`). | gebruiker, met hulp |
| 0.3 | `CLAUDE.md` verwijst voor de architectuur al naar `docs/ARCHITECTURE.md`. Controleer dat de regel klopt. | Opus |

---

## Fase 1 – Projectopzet, inloggen, onboarding, doelberekening

Uitkomst: iemand kan een account maken, de onboarding doorlopen en zijn dagdoel zien en aanpassen, in de nieuwe vormgeving, offline bruikbaar na de eerste keer.

### 1.1 Design system "Verzamelfiguren" — al gebouwd

Staat op branch `fase-1-opbouw`, met tests. 1.1 en 1.4 tot en met 1.8 zijn in één keer gebouwd: het startscherm verwijst naar alle schermen, en lege tussenschermen mogen niet (CLAUDE.md). Hieronder de oorspronkelijke opdracht, als naslag.

- **Doel:** kleuren, afstanden, knoppen, naamplaatje, doelenkaart en de vier figuren staan in `Fitling/DesignSystem`.
- **Bestanden:** overnemen van `herontwerp-verzamelfiguren`: `Fitling/DesignSystem/*` (`Spacing`, `Buttons`, `NamePlate`, `TargetsCard`, `NavigationBarStyle`, `Figures`), `Fitling/Resources/Assets.xcassets/*.colorset`, de sleutels `creature.*` in de String Catalog, `FitlingTests/FigureTests.swift`, `FitlingTests/NavigationBarStyleTests.swift`, en `.impeccable/surfaces/fitling.md` (het richtingscontract). Neem de stand van commit `c035b4d` of later: daarin zijn de bevindingen uit de eerste simulator-screenshots al opgelost (inkt in plaats van systeemblauw, `footerStyle()` voor leesbare toelichtingen, navigatietitels met een maximale grootte).
- **Ook overnemen:** de regel `sudo xcode-select -s /Applications/Xcode_16.4.app` in de stap "Toolchain" van `.github/workflows/ci.yml` (Xcode vastzetten; open punt uit de eindreview).
- **Aanpassen:** `Species` komt nu uit FitlingCore. Verwijder het enum uit `Figures.swift` en maak van `ribbon`, `tint`, `nameKey`, `noteKey` en `parts` een `extension Species`. `NavigationBarStyle.apply()` aanroepen in `FitlingApp.init`, en `.fontDesign(.rounded)` en `.tint(Color.ink)` op de root zetten. Lijsten van onboarding, profiel en inloggen krijgen `.foregroundStyle(Color.ink)`; toelichtingen onder een sectie `.footerStyle()`. Accountschermen niet: de rode verwijderknop moet rood blijven.
- **Acceptatie:** `FigureTests` groen; geen verwijzing meer naar `Color.paper`, `Rule` of `TargetsComposition`.
- **Tests:** `FigureTests` (3 tests × 4 soorten) en `NavigationBarStyleTests`.
- **Mac-run:** samen met 1.4.

### 1.2 Services: Supabase en inloggen — al gebouwd

Staat op branch `fase-1-opbouw`, met tests. `AuthService.failure(inLink:)` herkent de verlopen link (`AuthFailure.expiredLink`); de tekst `auth.reset.linkExpired` staat in de catalogus en wordt in 1.5 getoond. Hieronder de oorspronkelijke opdracht, als naslag.

- **Doel:** `AuthService` is de enige plek die met Supabase Auth praat.
- **Bestanden:** overnemen uit `fase-1`: `Fitling/Services/AuthProviding.swift`, `AuthService.swift`, `AppleSignIn.swift`, `NetworkMonitor.swift`, de functie `makeSupabaseClient` (stond in `Fitling/Data/ProfileSync.swift` of ernaast; zoek met `git grep makeSupabaseClient origin/fase-1`), `Fitling/UITesting/FakeAuthProvider.swift`, en de tests `AuthServiceMappingTests`, `AppleSignInTests`.
- **Aanpassen (open punt uit de eindreview):** een verlopen of al gebruikte link gaf de melding "werkt alleen op het toestel waar je hem hebt aangevraagd". Geef `AuthFailure` een geval `.expiredLink` voor redirects met `error_code=otp_expired` en een eigen tekst "Deze link is verlopen. Vraag een nieuwe aan."
- **Acceptatie:** dezelfde tests als in `fase-1` plus één voor de verlopen link.
- **Mac-run:** samen met 1.4.

### 1.3 SyncEngine — al gebouwd

Staat op branch `fase-1-opbouw`, met tests (`SyncEngineTests`, `SyncRecordTests`, nep-server `FakeRemoteStore`). Voor een volgende tabel: een record in `Fitling/Data/Sync/Records/` met eigen `encode(to:)` (geen `synced_at`, lege waarden als null), het model `SyncableModel` maken, en `ModelTable<Model>()` op de plek van §3.5 in de lijst zetten. `SyncEngine.sync()` geeft `.completed`, `.offline`, `.failed` of `.alreadyRunning`; `problemKey` is de catalogussleutel van een melding, of nil. Het aanmaken van de engine en de momenten waarop hij draait (§3.5) horen bij 1.4. Hieronder de oorspronkelijke opdracht, als naslag.

- **Doel:** één generieke sync volgens ARCHITECTURE §3, eerst voor `profiles` en `target_history`.
- **Gebruikt:** `SyncRules` uit FitlingCore voor elke beslissing: `pullAction(local:remote:)`, `pullStart(cursor:lastPull:now:)`, `nextCursor`, `canClearPushFlag`, en de constanten voor blokgrootte en overlap. De engine bevat zelf geen `if` over tijden of vlaggen.
- **Bestanden:** `Fitling/Data/Sync/SyncEngine.swift`, `SyncTable.swift` (per tabel: naam, sleutelkolom, model ↔ record), `RemoteStore.swift` (protocol met `upsert` en `fetch(since:limit:)`, de echte versie met Supabase en een nep-versie voor tests), `Records/ProfileRecord.swift`, `Records/TargetPeriodRecord.swift`.
- **Vastgelegd:**
  - Eén engine met een lijst tabellen in de volgorde van §3.5; geen aparte sync-klasse per tabel.
  - Records zijn `Codable` structs met `snake_case`-sleutels; `synced_at` wordt gelezen maar nooit verstuurd; een dag is `Day` (codeert als `"2026-11-18"`).
  - De engine draait op de main actor en gebruikt `container.mainContext`; hij houdt de `ModelContainer` zelf vast (les uit fase 1: anders verdwijnt de store onder een vertraagde push vandaan).
  - Push per 200, pull per 500, overlap 5 minuten, cursor in `SyncCursor`.
  - Pull zoekt lokaal op id en werkt bij of voegt toe; hij vertrouwt niet op `@Attribute(.unique)` om samen te voegen.
- **Acceptatie en tests** (`FitlingTests/SyncEngineTests.swift`, met de nep-`RemoteStore`):
  - `pushSendsOnlyRowsThatNeedIt`
  - `pushKeepsTheFlagWhenTheRowChangedMeanwhile`
  - `pushRemovesARowLocallyOnceItsDeletionIsOnTheServer`
  - `pullAddsNewRowsAndMovesTheCursor`
  - `pullKeepsANewerLocalChange`
  - `pullOverwritesAnOlderLocalRow`
  - `pullRemovesRowsTheServerMarkedDeleted`
  - `pullAsksAgainFromFiveMinutesBeforeTheCursor`
  - `aRejectedRowDoesNotBlockTheOthers` (en `problemKey` is gezet)
  - `onlyOneRoundRunsAtATime`
  - `oldCursorClearsTheTableAndPullsEverything` (laatste pull ouder dan 90 dagen)
  - `aQuietTableIsNotClearedWhileTheDeviceKeepsPulling`
  - `engineKeepsItsStoreAlive`
- **Mac-run:** ja, één.
- **→ Fable** bij een sync-fout die je niet in één poging begrijpt.

### 1.4 Start en routering — al gebouwd

Staat op branch `fase-1-opbouw`, met tests. 1.1 en 1.4 tot en met 1.8 zijn in één keer gebouwd: het startscherm verwijst naar alle schermen, en lege tussenschermen mogen niet (CLAUDE.md). Hieronder de oorspronkelijke opdracht, als naslag.

Wat anders is dan hieronder staat:
- `SyncEngine.sync()` tijdens een lopende ronde wacht op één extra ronde en geeft daarvan de uitkomst; `.alreadyRunning` bestaat niet meer. Nieuw: `.interrupted`.
- `SyncEngine.eraseLocalData()` wist alle modellen. Een verzoek dat terugkomt na een wis-actie wordt weggegooid, zodat rijen van de vorige gebruiker niet terugkomen.
- Uitloggen en account verwijderen wissen zelf niets: `RootViewModel.refresh()` wist bij `.signedOut` en toont in dezelfde stap welkom. Zo is er geen moment met het profielscherm zonder profiel.
- De eerste echte sync tegen het ontwikkelproject is nog niet gedaan; die wacht op 0.2 (RISKS R-21).

- **Doel:** `FitlingApp` maakt de services en toont het juiste scherm: laden, welkom, e-mail bevestigen, geen verbinding, onboarding of thuis.
- **Bestanden:** `Fitling/App/FitlingApp.swift` (uitbreiden), `RootViewModel.swift`, `RootView.swift`, `Fitling/UITesting/UITestEnvironment.swift` (overnemen), `FitlingTests/RootViewModelTests.swift` (uit `AppFlowTests` van `fase-1`).
- **Aanpassen (open punten uit de eindreview):**
  - ViewModels van schermen leven in `@State` van hun View, niet als `let` die bij elke render opnieuw wordt gemaakt.
  - `refresh()` krijgt een volgnummer: het resultaat van een oudere ronde wordt genegeerd als er een nieuwere is gestart.
  - Na uitloggen niet kort "Geen verbinding" tonen: zonder lokaal profiel én zonder sessie direct naar welkom.
- **Acceptatie:** de tests van `RootViewModel` uit `fase-1` groen, plus `olderRefreshDoesNotOverwriteANewerOne` en `signOutGoesStraightToWelcome`. `LaunchTests` aanpassen: uitgelogd starten toont de welkomknoppen.
- **Mac-run:** ja, met 1.1 en 1.2.

### 1.5 Welkom en inloggen met e-mail — al gebouwd

Staat op branch `fase-1-opbouw`, met tests. 1.1 en 1.4 tot en met 1.8 zijn in één keer gebouwd: het startscherm verwijst naar alle schermen, en lege tussenschermen mogen niet (CLAUDE.md). Hieronder de oorspronkelijke opdracht, als naslag.

- **Doel:** welkom (catalogus van de vier figuren, Apple, Google, e-mail), inloggen, registreren, wachtwoord vergeten, nieuw wachtwoord, e-mail bevestigen.
- **Bestanden:** `Fitling/Features/Auth/*` uit `herontwerp-verzamelfiguren` (die versies hebben de nieuwe look), `AuthViewModels.swift` en `AuthViewModelTests.swift` + `DoubleTapSupport.swift` uit `fase-1`.
- **Vastgelegd:** wachtwoord vergeten toont altijd dezelfde melding (D-03). Een link die `AuthFailure.expiredLink` geeft, toont `auth.reset.linkExpired`; `.invalidOrForeignLink` blijft `auth.reset.linkInvalid`. De Apple-knop staat bovenaan, even hoog als de andere, als capsule.
- **Nog open (gebruiker):** de Google-knop heeft nog geen G-logo. Het officiële logo downloaden mag pas na akkoord van de gebruiker; tot dan alleen tekst.
- **Acceptatie:** de ViewModel-tests uit `fase-1` groen; UI-test `testWelcomeScreen`; screenshot licht en donker naar de gebruiker.
- **Mac-run:** ja.

### 1.6 Onboarding — al gebouwd

Staat op branch `fase-1-opbouw`, met tests. 1.1 en 1.4 tot en met 1.8 zijn in één keer gebouwd: het startscherm verwijst naar alle schermen, en lege tussenschermen mogen niet (CLAUDE.md). Hieronder de oorspronkelijke opdracht, als naslag.

De omrekening van ft, in en lb zit in `BodyInput` (`Fitling/Features/Profile/BodyInput.swift`), gedeeld met het bewerkscherm. De geboortedag gaat via `BirthDayPicking`.

- **Doel:** toestemming, geboortedag, geslacht, lengte, gewicht, activiteit, doel, resultaat.
- **Gebruikt:** `NutritionEngine.plan(for:on:)`, `isValidBirthDay`, `Limits`, `Day`, `UserProfile`, `TargetPeriod`.
- **Bestanden:** `Fitling/Features/Onboarding/*` (schermen uit `herontwerp-verzamelfiguren`, ViewModel en tests uit `fase-1`).
- **Aanpassen:**
  - De geboortedag is een `Day`. De `DatePicker` werkt met een gregoriaanse kalender in UTC; omzetten met `Day(date, timeZone: UTC)`. `BirthDateCalendar` vervalt.
  - Alle omrekening (ft + in, lb) zit in het ViewModel, niet in de View; ook voor het bewerkscherm van 1.7.
  - Het resultaat toont, als `floorApplied` waar is, één regel: "We houden je doel boven een veilige ondergrens." (nieuwe sleutel `targets.floor`). Elke `TargetWarning` heeft een eigen tekst (`targets.warning.belowFloor`, `.belowCommonMinimum`, `.largeDeficit`); de bestaande `targets.warning.low` wordt de tekst voor `belowCommonMinimum`.
  - Bij afronden: `UserProfile` én een eerste `TargetPeriod` met `effectiveOn = vandaag`.
  - De toelichting bij de doelen noemt vaste percentages (20 %, 10 %, 5 %). Laat de tekst het getal uit `Goal.kcalFactor` invullen, zodat tekst en rekenregel niet uit elkaar lopen.
- **Tests:** `OnboardingViewModelTests` uit `fase-1` aangepast aan `Day`, plus:
  - `defaultBirthDayIsThirtyYearsAgoInAnyTimeZone` (met `TimeZone(identifier: "America/Los_Angeles")`)
  - `imperialHeightAndWeightGiveTheSameProfileAsMetric`
  - `finishStoresTheProfileAndTheFirstTargetPeriod`
  - `resultExplainsTheFloorWhenItWasApplied`
- **Acceptatie:** UI-test loopt de hele flow door in licht, donker en bij de grootste tekst (alle acht stappen, "Verder" steeds bereikbaar), met een screenshot per stap.
- **Mac-run:** ja.

### 1.7 Dagdoel en profiel — al gebouwd

Staat op branch `fase-1-opbouw`, met tests. 1.1 en 1.4 tot en met 1.8 zijn in één keer gebouwd: het startscherm verwijst naar alle schermen, en lege tussenschermen mogen niet (CLAUDE.md). Hieronder de oorspronkelijke opdracht, als naslag.

Een wijziging wordt direct opgeslagen en twee seconden later gesynct. Een doelwijziging maakt of werkt de `TargetPeriod` van vandaag bij (`ModelContext.recordTargets`).

- **Doel:** het dagdoel met uitleg (BMR, TDEE, factoren), profiel bewerken, doelen handmatig aanpassen.
- **Gebruikt:** `NutritionEngine.plan`, `NutritionEngine.warnings(forKcal:bmr:tdee:sex:)`, `TargetsCard`.
- **Bestanden:** `Fitling/Features/Profile/*` (schermen uit `herontwerp-verzamelfiguren`, ViewModel uit `fase-1`).
- **Aanpassen:**
  - Elke wijziging van de doelen maakt een `TargetPeriod` voor vandaag (bestaat er al een voor vandaag, dan die bijwerken).
  - Elke wijziging slaat direct op met `context.save()`.
  - Een handmatig doel toont de waarschuwingen van `warnings(forKcal:…)` en blokkeert niet (D-10).
- **Tests:** de `ProfileViewModel`-tests uit `fase-1`, plus `changingTargetsStartsANewPeriodToday`, `changingTargetsTwiceOnOneDayKeepsOnePeriod`, `manualTargetBelowTheFloorWarnsButSaves`, `editSavesImmediately`.
- **Mac-run:** ja.

### 1.8 Account — al gebouwd

Staat op branch `fase-1-opbouw`, met tests. 1.1 en 1.4 tot en met 1.8 zijn in één keer gebouwd: het startscherm verwijst naar alle schermen, en lege tussenschermen mogen niet (CLAUDE.md). Hieronder de oorspronkelijke opdracht, als naslag.

- **Doel:** uitloggen (met waarschuwing bij onverstuurde wijzigingen) en account verwijderen.
- **Bestanden:** `Fitling/Features/Account/*` en `AccountViewModel` + tests uit `fase-1`; `supabase/functions/delete-account` bestaat al.
- **Aanpassen (open punt uit de eindreview):** `delete-account/index.ts` start nu met een lege sleutel als `SUPABASE_SECRET_KEYS` ontbreekt. Laat de functie bij het starten duidelijk loggen wat ontbreekt en `500 misconfigured` teruggeven; test erbij.
- **Acceptatie:** tests uit `fase-1` groen; Deno-tests groen.
- **Mac-run:** ja, samen met 1.7.

### 1.9 Afronden fase 1 — al gedaan

Gedaan op 2026-11-19: screenshots van alle schermen in licht, donker en grootste tekst (UI-test `OnboardingFlowTests`), finish-review en de reparaties daaruit, codereview en de reparaties daaruit, `DESIGN.md`. Open en vastgelegd in `docs/UNFORGET.md`: S11 (op een echt toestel nakijken), S12 (een sessie die vanzelf afloopt wist onverstuurde wijzigingen; ontwerpkeuze). Hieronder de oorspronkelijke opdracht, als naslag.

- Screenshots van alle schermen (licht, donker, grootste tekst) naar de gebruiker.
- `impeccable` finish-review op de schermen en daarna `impeccable:impeccable-documenter` voor `DESIGN.md`.
- Open punten in `docs/UNFORGET.md` via de skill `unforget`.
- Bekend gat in `scripts/check-strings.mjs`: een losse zin in een ternary of in een `switch` die een `LocalizedStringKey` teruggeeft, wordt niet gezien. Schrijf sleutels daar altijd voluit en loop de schermen na in en en de.
- Merge naar `main` na akkoord.

---

## Fase 2 – Voeding loggen

### 2.1 Sync voor voeding

- **Doel:** `products` (alleen eigen rijen pushen), `food_entries`, `water_entries`, `favorite_products` in de `SyncEngine`.
- **Bestanden:** `Fitling/Data/Sync/Records/*` en de tabellijst.
- **Tests:** per tabel een heen-en-terug-test van het record (`recordKeepsEveryColumn`), en `sharedProductsAreNeverPushed`.

### 2.2 FoodMath (FitlingCore) — al gebouwd

`FoodMath` staat in FitlingCore, met tests. Gebruik in 2.3, 2.6 en 2.7:

- `FoodMath.nutrients(per100:quantity:unit:servingSize:)` geeft de waarden van één log, of `nil` als het product geen kcal heeft of porties niet kunnen (geen `servingSize`).
- `FoodMath.totals(_:)` geeft `DayTotals`: onbekende macro's tellen als 0 en worden geteld in `unknownProtein`, `unknownCarbs`, `unknownFat`.
- `FoodMath.kcal(fromKilojoules:)` en `FoodMath.isConsistent(kcal:proteinG:carbsG:fatG:)`. De Edge Function `lookup-product` is TypeScript en bouwt deze twee regels na met dezelfde getallen (4,184; 25 % én 30 kcal); neem de testgevallen uit `FoodMathTests` over.

### 2.3 Edge Function `lookup-product`

- **Doel:** ARCHITECTURE §5 stap 2a en 2b.
- **Bestanden:** `supabase/functions/lookup-product/{index.ts,handler.ts,openfoodfacts.ts,normalize.ts,ratelimit.ts,deno.json}` en tests; `supabase/config.toml` (`verify_jwt = false`, de functie controleert het token zelf, zoals `delete-account`).
- **Vastgelegd:** invoer `{ "gtin": "…" }` (al genormaliseerd; de functie controleert het controlecijfer opnieuw). Uitvoer de rij uit `products`. Fouten: `400 invalid_gtin`, `401`, `404 not_found`, `429 rate_limited`, `502 source_unavailable` (na drie pogingen). 60 aanroepen per gebruiker per uur via `private.rate_limits` (sleutel `lookup:<user>`, venster afgerond op het uur).
- **Tests (Deno, met een vastgelegd antwoord van Open Food Facts als bestand):** `returnsTheCachedProductWithoutCallingTheSource`, `refreshesAProductOlderThanThirtyDays`, `storesANewProductOnce` (twee gelijktijdige aanroepen, één rij), `convertsKilojoulesWhenKcalIsMissing`, `leavesMissingNutrientsEmpty`, `dropsValuesOutsideTheirLimits`, `marksAnInconsistentLabelAsUnverified`, `retriesThreeTimesOnA503`, `rejectsAWrongCheckDigit`, `limitsCallsPerUserPerHour`.
- **Controleer** de veldnamen van Open Food Facts met één echte aanroep vóór je het testbestand vastlegt.

### 2.4 ProductLookup (app)

- **Doel:** lokaal → `lookup-product` → niet gevonden, met de regels van §5 (30 dagen, offline).
- **Bestanden:** `Fitling/Services/ProductLookup.swift` (protocol `ProductLookingUp` + echte en nep-versie).
- **Tests:** `usesTheLocalProductWhenFresh`, `asksTheServerWhenStale`, `keepsTheStaleProductWhenOffline`, `reportsNotFound`, `invalidBarcodeNeverReachesTheServer`.

### 2.5 Scannen

- **Doel:** `DataScannerViewController` voor EAN-13, EAN-8 en UPC-A; het resultaat gaat door `Barcode.normalized`.
- **Let op:** de simulator heeft geen camera. De UI-test gebruikt een DEBUG-startargument dat een barcode aanlevert. Echt scannen is "gebouwd, niet bewezen" tot TestFlight.
- **Tests:** ViewModel: `scanOfAKnownProductOpensTheLogSheet`, `scanOfAnUnknownProductOffersToAddIt`, `misreadIsIgnored`.

### 2.6 Loggen

- **Doel:** zoeken op naam, recent, favorieten, maaltijd kiezen, hoeveelheid in gram/ml of porties, opslaan als `FoodEntry` met momentopname.
- **Vastgelegd:** zoeken eerst lokaal, online daarna in `products` met `search_name ilike '%' || term || '%'` (de trigram-index maakt dat snel), hoogstens 30 resultaten. "Recent" is de laatste 20 verschillende producten uit `FoodEntry`. Een product zonder kcal kan pas gelogd worden na aanvullen (§5.2).
- **Tests:** `loggingStoresASnapshotOfNameAndValues`, `editingAProductLaterDoesNotChangeOldEntries`, `productWithoutKcalAsksForIt`, `recentShowsEachProductOnce`.

### 2.7 Dagoverzicht

- **Doel:** kcal-ring, eiwit/koolhydraten/vet, water, per maaltijd de logs.
- **Gebruikt:** `FoodMath.DayTotals`, `TargetPeriod` (het doel dat op die dag gold), `NutritionEngine.dayTargets`.
- **Vastgelegd:** de ring en de macro-linten vullen zich in de kleuren uit het design system, zonder verloop. Onbekende macro's worden gemeld (§5.2).
- **Tests:** `usesTheTargetsThatAppliedOnThatDay`, `reportsUnknownMacros`, `waterAddsUp`.

### 2.8 Zelf een product toevoegen

- **Doel:** foto verpakking + etiket, Vision leest het etiket, gebruiker controleert, `submit-product` slaat op.
- **Bestanden:** `supabase/functions/submit-product/*`; een privé Storage-bucket `product-photos` met policies (alleen eigen map `<user-id>/…`); `delete-account` verwijdert ook de bestanden van de gebruiker.
- **Tests:** Deno: `rejectsValuesOutsideLimits`, `createsTheSharedRowOnce`, `keepsTheSubmission`; pgTAP of Deno: een gebruiker kan alleen de eigen map lezen en schrijven; `deleteAccountRemovesThePhotos`.

### 2.9 NEVO importeren

- **Vooraf (gebruiker):** RISKS R-03 beantwoord.
- **Doel:** een script dat de NEVO-tabel inleest en als gedeelde rijen (`source = 'nevo'`, `is_verified = true`) schrijft.

### 2.10 Afbeeldingen

- **Doel:** productfoto's laden en bewaren (`URLCache`), met een getekende placeholder in de stijl van het design system. Geen AI-foto's.

---

## Fase 3 – Partner

TestFlight (UNFORGET S1) moet er vóór deze fase zijn: meldingen, widget en Live Activity zijn in de simulator niet te bewijzen.

### 3.1 Partner kiezen

- **Doel:** soort, naam (1–24 tekens), kleur (0–2) en toon kiezen; opslaan als `Creature`. Bestaande gebruikers krijgen de stap bij de eerste start na de update.
- **Gebruikt:** `CreatureState`, `Creature`, de figuren uit het design system.
- **Tests:** `setupStoresTheChoices`, `nameIsTrimmedAndLimited`, `existingUserIsAskedOnce`.

### 3.2 Dagen samenstellen en verwerken

- **Doel:** uit de lokale data een lijst `DayRecord` maken en de partner bijwerken.
- **Bestanden:** `Fitling/Data/CreatureHistory.swift`.
- **Vastgelegd:** per dag: som van de logs (kcal, eiwit, aantal), het doel uit `TargetPeriod` met `NutritionEngine.dayTargets` als trainingen meetellen, en "training voltooid" als er die dag een `WorkoutSession` met `endedAt` is of HealthKit een training meldt. Aanroepen bij app-start en als de dag wisselt: `CreatureEngine.advance`, daarna `creature.apply(_:at:)` en opslaan. Lever de records vanaf zes dagen vóór de laatst verwerkte dag.
- **Tests:** `buildsOneRecordPerDayWithLogs`, `usesTheTargetOfThatDay`, `workoutFromHealthKitCounts`, `advanceIsAppliedAndSavedOnce`.

### 3.3 De partner tekenen

- **Vastgelegd:** SwiftUI (`Canvas` + `TimelineView`), geen SpriteKit of Rive. Reden: de figuren zijn al vector, er komt geen library bij, en een widget kan dezelfde tekening gebruiken (SpriteKit en Rive kunnen dat niet).
- **Doel:** een View die een `CreatureSnapshot` tekent: vorm (0–1 als breedte van het lijf), stemming (ogen en mond), energie (tempo van de beweging), groeistadium per soort, accessoires, trainingsbonus. Met "Verminder beweging" aan staat het stil.
- **Acceptatie:** screenshots van elke soort in elke toestand naar de gebruiker; die keurt de tekeningen.

### 3.4 Level, XP en vrijspelen

- **Doel:** voortgang naar het volgende level, wat `CreatureEvent` meldt (level, accessoire, kleur, herstelbonus), accessoires aan- en uitdoen (`equippedItems`).

### 3.5 Meldingen

- **Vastgelegd:** lokale meldingen (`UNUserNotificationCenter`), geen server. Hoogstens twee per dag, niet tussen 21:00 en 08:00, tijden instelbaar, alles uit te zetten. Onderwerp via `CreatureEngine.topic(for:)`, tekst via `messageKey(topic:tone:on:)`.
- **Tests:** `schedulesAtMostTwoPerDay`, `neverSchedulesAtNight`, `nothingIsScheduledWhenTurnedOff`.

### 3.6 Teksten van de meldingen

- **Doel:** 6 onderwerpen × 3 tonen × 3 varianten in nl, en en de (162 teksten per taal). Vriendelijk, nooit beschamend, kort. De gebruiker leest de Nederlandse set na vóór de vertaling.
- **Voorbeelden van de gebruiker** voor `hungry`: lief "Ik heb honger 🥺", grappig "Mijn maag knort harder dan jouw wekker", coach "Tijd voor eiwit. Wat eet je?".

### 3.7 Widget

- **Doel:** de partner op het beginscherm. Vraagt een App Group om de snapshot te delen (UNFORGET S1).

### 3.8 Live Activity

- **Doel:** de partner tijdens een maaltijdmoment of training (PROMPT.md §2). Bepaal met de gebruiker wanneer hij start en stopt vóór je bouwt.

### 3.9 Afstelling herzien — **→ Fable**

Na twee tot vier weken echt gebruik: kloppen de drempels, de snelheid van de vorm, de XP en de levels met hoe het voelt? Alleen Fable past `CreatureEngine` aan.

---

## Fase 4 – Sport

### 4.1 Oefeningen en schema's vullen

- **Doel:** de gedeelde oefeningen en de drie schema's (Full body 3×, Upper/Lower 4×, PPL 6×) als databestand en een script dat ze schrijft.
- **Vastgelegd:** per oefening `kind`, `load_type`, `equipment`, spieren en `default_step_kg` (barbell 2,5 · dumbbell 2 · machine en cable 5 · kettlebell 4 · lichaamsgewicht 2,5). Namen en instructies in nl, en en de. Afbeeldingen alleen rechtenvrij of zelf getekend.

### 4.2 Sync voor sport

- `exercises`, `programs`, `program_days`, `program_exercises` (alleen eigen rijen pushen), `exercise_settings`, `workout_sessions`, `workout_sets`, `body_measurements`.

### 4.3 Schema's kiezen en zelf maken

### 4.4 Training loggen

- **Doel:** sets, herhalingen, gewicht, RPE, warming-up-vinkje, rusttimer met Live Activity.
- **Tests:** `finishingSetsEndedAt`, `restTimerStartsAfterASet`, `weightIsStoredInKilograms` (invoer in lb wordt omgerekend).

### 4.5 Progressie-advies

- **Gebruikt:** `ProgressionEngine.advise`, `personalRecords`, `ExerciseSetting`.
- **Vastgelegd:** de geschiedenis is per oefening de lijst trainingen met alleen werksets (`WorkoutSet.workingSet`). De regels komen uit `ExerciseSetting` als die er is, anders uit het schema en de oefening. Elk advies heeft één zin tekst en één knop om het over te nemen.
- **Tests:** `adviceUsesTheUsersOwnStep`, `warmUpSetsAreIgnored`, `acceptingAdvicePrefillsTheNextSet`.

### 4.6 Grafieken

- **Gebruikt:** `estimatedOneRepMax`, `weeklyVolume`, Swift Charts.

### 4.7 HealthKit

- **Vastgelegd:** alleen lezen: trainingen, stappen, actieve energie. Trainingsenergie per dag naar `DayActivity`. De schakelaar `countsWorkoutEnergy` staat standaard uit. Niets hiervan gaat naar Supabase (D-19).
- **Tests:** met een nep-`HealthReading`: `storesWorkoutEnergyPerDay`, `budgetGrowsOnlyWhenTheSwitchIsOn`.

### 4.8 Lichaamsgewicht en omtrekken

### 4.9 Voortgangsfoto's

- **Vastgelegd:** alleen lokaal, in de eigen map van de app, met `isExcludedFromBackup`. Nooit naar de server.

---

## Fase 5 – Recepten en weekmenu

### 5.1 Recepten vullen en syncen

- **Vooraf (gebruiker):** waar komen de recepten en hun foto's vandaan? Het moeten echte foto's zijn die bij het recept horen.

### 5.2 Recepten bekijken en zelf maken

### 5.3 Voorkeuren

- `MenuPreferences` en `ExcludedIngredient`.

### 5.4 Weekmenu maken

- **Gebruikt:** `WeekMenuPlanner.plan`, `Recipe.plannerRecipe(ingredientIDs:)`, `MealPlanEntry`.
- **Vastgelegd:** "Nieuw menu" is hetzelfde verzoek met een ander `seed`. Vastzetten zet `isPinned`; wisselen en verslepen passen `MealPlanEntry` aan en zetten hem vast. Elk `MenuIssue` wordt in gewone taal getoond.
- **Tests:** `generatingStoresOneEntryPerPlannedMeal`, `pinnedMealsSurviveANewMenu`, `issuesAreShown`.

### 5.5 Loggen met één tik

- **Vastgelegd:** maakt een `FoodEntry` uit het recept en de porties en zet `loggedEntryID`; een tweede tik doet niets.

### 5.6 Kwaliteit van de menu's — **→ Fable** als de menu's in de praktijk eentonig of onhaalbaar zijn.

---

## Fase 6 – Boodschappenlijst en aanbiedingen

### 6.1 ShoppingListBuilder (FitlingCore) — al gebouwd

`ShoppingListBuilder.lines(for:)` maakt uit het weekmenu één lijst: per product en eenheid opgeteld, naar boven afgerond op wat je kunt kopen, in de volgorde van de winkel. Geef per `MealPlanEntry` één `PlannedRecipeUse` mee, ook voor restjes: een restje is een portie uit dezelfde pan en hoort dus bij wat er gekocht wordt.

### 6.2 Lijst en items

- **Vastgelegd:** de eerste lijst wordt lokaal aangemaakt, ook offline: `ShoppingList` + `ShoppingListMember` als eigenaar. Items van het menu hebben `source = "menu"` en worden vervangen als het menu verandert; handmatige items blijven.

### 6.3 Delen

- **Gebruikt:** `create_shopping_list_invite`, `join_shopping_list`, Realtime als seintje om te pullen (D-18).

### 6.4 `sync-offers`

- **Vooraf (gebruiker):** RISKS R-13 beantwoord. Zonder bron: alleen de provider met testdata.

### 6.5 OfferMatcher (FitlingCore) — al gebouwd

`OfferMatcher.matches(items:offers:on:ignoredWords:)`, `cheapestPerItem` en `storeTotals` staan in FitlingCore, met tests (ARCHITECTURE §6.1). In de app: geef de namen van de favoriete supermarkten mee als `ignoredWords`, en bewaar lokaal welke onzekere aanbiedingen de gebruiker met "Klopt" heeft bevestigd (`confirmedOfferIDs`).

### 6.6 Kwaliteit van de matches — **→ Fable** als er te veel verkeerde of gemiste matches zijn.

### 6.7 Aanbiedingen tonen

- Favoriete supermarkten, postcode, per item de goedkoopste winkel, totaal per winkel met "+ n items zonder prijs".

---

## Fase 7 – Afronden

| Nr | Wat |
|---|---|
| 7.1 | Alle teksten nalopen in nl, en en de; eenheden via `Measurement` (kg/lb, kcal/kJ) |
| 7.2 | Toegankelijkheid: VoiceOver op elk bedieningselement, grootste tekst, contrast |
| 7.3 | Data-export (JSON en CSV) van alle eigen data |
| 7.4 | Opruimen van verwijdermarkeringen ouder dan 90 dagen (geplande job). De 90 dagen tellen vanaf `synced_at` (klok van de server), niet vanaf `deleted_at` (klok van een toestel): een toestel leegt zijn tabel pas na 90 dagen zonder pull, en een markering die eerder verdwijnt bereikt dat toestel nooit. Laat de job 's nachts draaien: een pull van meer dan één blok kan een rij missen als er tijdens het lezen rijen echt verdwijnen (ARCHITECTURE §3.4). |
| 7.5 | `schema.sql` wordt de eerste migratie; productieproject in de EU (UNFORGET S4) |
| 7.6 | Privacyverklaring gelinkt; scherm "Over" met bronvermelding (Open Food Facts, NEVO) |
| 7.7 | TestFlight, app-icoon, eigen SMTP (UNFORGET S1 en S2) |
| 7.8 | Laatste ronde vormgeving met `impeccable` |

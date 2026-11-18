# Fitling – architectuur, mappenstructuur en datamodel

Datum: 2026-11-18 · Status: goedgekeurd op 2026-11-18 · Bron: `PROMPT.md`, `CLAUDE.md`

## 1. Wat en waarom

Fitling is een native iOS-app (iOS 17+) die voeding loggen, trainen en een tamagotchi-achtig wezentje combineert. Het wezentje reageert op hoe je eet en traint. Het einddoel is TestFlight en de App Store (PROMPT.md fase 7, App Store-eis "account verwijderen").

Dit document is de eerste stap uit PROMPT.md: architectuur, mappenstructuur, SwiftData-modellen en het Supabase-schema. Er wordt niets gebouwd tot het is goedgekeurd. Het datamodel staat hier op hoofdlijnen voor alle fases. De volledige code (Swift en SQL) staat er alleen voor fase 1 in; zie §4.4 voor waarom.

## 2. Doelen, niet-doelen, anti-doelen

**Doelen fase 1** (PROMPT.md "Fases" punt 1)
- Projectopzet die op een Mac van GitHub bouwt en test.
- Inloggen met Apple, Google en e-mail/wachtwoord, met e-mailverificatie en wachtwoord vergeten.
- Account verwijderen in de app.
- Onboarding: toestemming voor gezondheidsgegevens, geboortedatum (18+), geslacht, lengte, gewicht, activiteitsniveau, doel.
- Doelberekening: BMR (Mifflin-St Jeor), TDEE, kcal-doel en macro's. De gebruiker kan alles aanpassen, ook het profiel achteraf.
- Offline-first: het profiel staat lokaal in SwiftData en wordt gesynchroniseerd met Supabase.

**Niet-doelen fase 1**
- Voeding loggen, het wezentje, sport, recepten, boodschappen (fases 2–6).
- TestFlight en code signing. Dat komt later (jouw keuze), zie §2.1.
- Data-export, privacyverklaring, eigen e-mailserver. Die zijn nodig voordat anderen de app gebruiken, niet om fase 1 te bouwen.
- Widgets, Live Activities en pushmeldingen (fase 3).

**Anti-doelen** (een mislukking, ook als het technisch werkt)
- AI slop volgens CLAUDE.md: placeholders, TODO's, verzonnen API's, overbodige lagen, generieke AI-look, wollige teksten.
- "Klaar" melden zonder groene build en tests.
- Geheime sleutels in de app.
- Een wezentje of teksten die beschamen.

### 2.1 Wat fase 1 wel en niet bewijst

Zonder Mac en zonder TestFlight draait de app in fase 1 alleen in de simulator op de Mac van GitHub. Jij ziet de schermen via screenshots uit de CI.

- **Wel bewezen:** de app bouwt, de rekenregels kloppen, ViewModels en SwiftData doen wat ze moeten, de onboarding loopt door, RLS en de database werken, de Edge Function `delete-account` doet het met nagebootste antwoorden.
- **Niet bewezen tot TestFlight:** echt inloggen met Apple, Google en e-mail, de links in de e-mails, het intrekken van het Apple-token en de sync met je echte Supabase-project. Die code wordt geschreven en getest met nep-implementaties. Een echte test op een toestel komt pas als je het Apple Developer Program neemt.
- **Advies:** neem TestFlight op uiterlijk vóór fase 3. Pushmeldingen, de widget en de Live Activity zijn zonder toestel niet te testen.

## 3. Randvoorwaarden

- **Geen Mac.** De ontwikkelpc draait Windows 11, zonder Xcode en zonder Swift. Bouwen en testen gebeurt op GitHub Actions (macOS-runner).
- **Privé-repo.** Inbegrepen: $12 per maand, ongeveer 190 macOS-minuten. De CI is daarop ingericht (§6).
- **Stack ligt vast** (PROMPT.md): Swift 6, SwiftUI, iOS 17, MVVM met `@Observable`, SwiftData, Supabase, SPM, zo min mogelijk externe libraries.
- **CLAUDE.md:** teksten alleen via `Localizable.xcstrings`, geen API-keys in de app, unit tests bij elke feature, werken per fase.
- **Minimumleeftijd 18** (jouw keuze).

### 3.1 Gekozen aanpak: bouwen op een Mac van GitHub

| | A. GitHub Actions macOS (**gekozen**) | B. Gehuurde cloud-Mac |
|---|---|---|
| Hoe | Push → Mac van GitHub draait `xcodegen` + `xcodebuild test` → testrapport en screenshots | Remote desktop naar een Mac mini met Xcode |
| Kosten | Privé: $12/maand inbegrepen (~190 macOS-minuten), daarna $0,062/min | Per uur, minimaal 24 uur, of ongeveer €149/maand |
| Voordeel | Elke wijziging automatisch bewezen. Past bij "alleen klaar als het bouwt en de tests slagen" | Zelf door de app klikken, snellere feedback |
| Nadeel | Je ziet de app pas echt via TestFlight of de screenshots uit de CI | Duurder, eigen beheer |

Afgevallen: Flutter/React Native (PROMPT.md schrijft Swift/SwiftUI voor).

Gevolgen voor de opzet:
- **XcodeGen** (`project.yml`) maakt het Xcode-project op de CI-Mac aan. `Fitling.xcodeproj` staat niet in git. Pakketversies staan daarom exact vast in `project.yml`, want het `Package.resolved` in het gegenereerde project wordt niet bewaard.
- **Rekenregels in een los Swift-pakket `FitlingCore`**, alleen afhankelijk van Foundation. Die tests draaien op een goedkope Linux-runner. Het pakket bevat later ook de wezentje-logica en de progressieregels; PROMPT.md vraagt juist daarvoor unit tests.
- **Supabase-migraties en RLS** worden op een Linux-runner getest met `supabase db start` + `supabase test db` (pgTAP).

## 4. Architectuur

### 4.1 Lagen

```
SwiftUI-views ──► ViewModels (@Observable, @MainActor)
                     │
                     ├─► AuthService (@Observable, @MainActor) ──► supabase-swift (Auth, Functions)
                     ├─► ModelContext (SwiftData, main context)
                     └─► ProfileSync (@MainActor)              ──► supabase-swift (PostgREST)
FitlingCore (puur Swift): enums, BMR/TDEE/macro's, grenzen; later wezentje en progressie
```

- **Views** bevatten geen logica. Ze lezen state van hun ViewModel.
- **ViewModels** per scherm of flow, `@Observable @MainActor final class`.
- **AuthService** is de enige plek die met Supabase Auth praat. Het luistert naar `supabase.auth.authStateChanges` en publiceert de inlogstatus: uitgelogd, wacht op e-mailverificatie, ingelogd.
  - De client krijgt `emitLocalSessionAsInitialSession = true`. Dan telt een opgeslagen sessie meteen bij een koude start, ook offline.
  - Een verlopen access token is geen uitlogreden. Een mislukte refresh door een netwerkfout laat de gebruiker ingelogd; alleen een expliciete weigering van de server logt uit.
- **ProfileSync** draait op de main actor en schrijft via de main context. De netwerkaanroepen zijn `async` en blokkeren de UI niet. Een aparte `@ModelActor`-context geeft op iOS 17/18 onbetrouwbare updates naar `@Query` en levert bij één profielrij niets op. In fase 2 komt een algemene synchronisatie voor logboeken; dan wordt de achtergrondcontext opnieuw afgewogen.
- **Eén protocol, `AuthProviding`**, met de echte `AuthService` en een nep-versie voor tests en de UI-test (§6). Verder geen protocollen zonder tweede implementatie.
- **Dependency injection** via SwiftUI `.environment(...)` vanuit `FitlingApp`. Geen service locator, geen singletons behalve wat het framework oplegt.

### 4.2 Externe afhankelijkheden

| Wat | Waarom | Waar |
|---|---|---|
| `supabase-swift` 2.x, product `Supabase` (`https://github.com/supabase/supabase-swift`), exacte versie in `project.yml` | Auth, PostgREST, Functions, later Storage en Realtime | App |
| XcodeGen | Xcode-project genereren zonder Mac | Alleen CI |
| Supabase CLI | Migraties en pgTAP-tests | Alleen CI |

Google-login loopt via de OAuth-flow van Supabase met `ASWebAuthenticationSession`. Dat scheelt de Google Sign-In SDK.

### 4.3 Mappenstructuur

```
Sportapp/                         (repo-root)
├── CLAUDE.md, PROMPT.md
├── project.yml                   XcodeGen: targets Fitling, FitlingTests, FitlingUITests; exacte pakketversies
├── Config/
│   ├── Shared.xcconfig           bundle id, deployment target, Swift 6
│   └── Supabase.xcconfig         SUPABASE_HOST + SUPABASE_PUBLISHABLE_KEY (niet in git; CI maakt hem aan uit secrets)
├── Fitling/
│   ├── App/                      FitlingApp.swift, RootView.swift
│   ├── Features/
│   │   ├── Auth/                 SignIn-, SignUp-, ForgotPassword-, ResetPassword-, VerifyEmail-views + ViewModels
│   │   ├── Onboarding/           OnboardingFlowView, stappen (toestemming t/m doel), OnboardingViewModel
│   │   ├── Profile/              ProfileView (dagdoel + uitleg), EditProfileView, EditTargetsView + ViewModels
│   │   └── Account/              AccountView (uitloggen, account verwijderen), AccountViewModel
│   ├── Data/
│   │   ├── Schema/               FitlingSchemaV1.swift, FitlingMigrationPlan.swift
│   │   ├── ProfileSync.swift
│   │   ├── ProfileRecord.swift   Codable-spiegel van de profiles-rij (snake_case ↔ camelCase)
│   │   └── BirthDateCalendar.swift  vaste gregoriaanse UTC-kalender voor geboortedata
│   ├── Services/                 AuthService.swift, AuthProviding.swift, AppleSignIn.swift
│   ├── UITesting/                alleen in DEBUG: nep-auth + in-memory store voor de UI-test (§6)
│   ├── DesignSystem/             Spacing.swift, kleuren als named colors in Assets
│   └── Resources/                Localizable.xcstrings, Assets.xcassets, Fitling.entitlements
├── FitlingTests/                 ViewModel- en SwiftData-tests (simulator, CI)
├── FitlingUITests/               één flowtest die screenshots per scherm bewaart
├── Packages/FitlingCore/
│   ├── Package.swift
│   ├── Sources/FitlingCore/      BodyProfile.swift, EnergyCalculator.swift, NutritionTargets.swift, Limits.swift
│   └── Tests/FitlingCoreTests/
├── supabase/
│   ├── config.toml
│   ├── migrations/20261118120000_profiles.sql
│   ├── tests/                    pgTAP: RLS, sync-regel, grenzen
│   └── functions/delete-account/index.ts
├── scripts/check-strings.mjs     controleert dat elke tekstsleutel nl/en/de heeft
└── .github/workflows/ci.yml
```

`Supabase.xcconfig` bevat alleen de host (`abcd.supabase.co`), want een xcconfig leest `//` als begin van commentaar. De app maakt er `https://` + host van.

Indeling per feature: alles van één scherm of flow staat bij elkaar. Volgende fases voegen mappen toe onder `Features/` (Food, Creature, Training, Recipes, Shopping) en onder `FitlingCore` (Creature, Training).

### 4.4 Datamodel op hoofdlijnen (alle fases)

De volledige SQL en Swift staan alleen voor fase 1 in dit document. Voor de latere fases is het ontwerp nog niet besproken (bijvoorbeeld: hoe werkt meal-prep precies?). Tabellen die nu al worden aangelegd, zouden later ongebruikt blijven of omgebouwd moeten worden. Elke fase begint daarom met het uitwerken van zijn eigen tabellen.

| Fase | Entiteit | Lokaal (SwiftData) | Server (Supabase) | Opmerking |
|---|---|---|---|---|
| 1 | Profiel + doelen + toestemming | `UserProfile` | `profiles` | 1 rij per gebruiker |
| 2 | Product | cache | `products` (gedeeld) | barcode, naam per taal, waarden per 100 g, bron off/nevo/user; schrijven alleen via Edge Function |
| 2 | Voedingslog | `FoodEntry` | `food_entries` | grammen + momentopname van kcal/macro's, zodat oude dagen niet veranderen als een product wordt bijgewerkt |
| 2 | Water | `WaterEntry` | `water_entries` | |
| 2 | Favorieten/recent | `FavoriteFood` | `favorite_foods` | |
| 3 | Wezentje | `Creature` | `creatures` | keuze, naam, XP, level, vrijgespeelde items; dagstatus wordt lokaal uit de logs berekend |
| 4 | Oefening | cache | `exercises` (gedeeld) | |
| 4 | Schema | `Program`, `ProgramExercise` | `programs`, `program_exercises` | kant-en-klaar (gedeeld) + eigen |
| 4 | Training | `WorkoutSession`, `WorkoutSet` | `workout_sessions`, `workout_sets` | |
| 4 | Metingen | `BodyMeasurement` | nog te beslissen | progressiefoto's alleen lokaal, nooit naar de server |
| 5 | Recept | cache + eigen | `recipes`, `recipe_ingredients` | |
| 5 | Weekmenu | `MealPlanEntry` | `meal_plan_entries` | |
| 6 | Boodschappen | `ShoppingItem` | `shopping_lists`, `shopping_list_members`, `shopping_items` | realtime gedeeld |
| 6 | Aanbiedingen | cache | `supermarkets`, `offers` | alleen de backend schrijft |

Regels voor elke tabel met gebruikersdata: `user_id` (of `id`) gekoppeld aan `auth.users` met `on delete cascade`, RLS aan, `updated_at` (klok van de client) en `synced_at` (klok van de server). Tabellen met meerdere rijen per gebruiker krijgen vanaf fase 2 ook `deleted_at` als verwijdermarkering.

### 4.5 Offline-first synchronisatie

- SwiftData is de bron van waarheid op het toestel. Elke wijziging zet `updatedAt = now` en `needsPush = true`.
- **Push:** `ProfileSync` stuurt het profiel met `needsPush` naar Supabase via `upsert`. Na succes wordt `needsPush` alleen gewist als `updatedAt` nog gelijk is aan de verstuurde waarde. Een wijziging die tijdens de push binnenkwam, gaat zo niet verloren.
- **Conflicten: laatste wijziging wint**, op basis van `updated_at`. Een trigger op de server negeert een update die ouder is dan wat er al staat (§5.2).
- **Pull:** na het inloggen en bij elke app-start met internet wordt de profielrij opgehaald. Is `updated_at` van de server nieuwer en is er lokaal niets onverstuurd, dan wordt de serverversie overgenomen.
- **Eerste keer op een toestel:** de onboarding start pas als een geslaagde pull bevestigt dat er op de server geen profiel is. Is er geen internet en geen lokaal profiel, dan toont de app "Verbind met internet om je profiel op te halen" met een knop om opnieuw te proberen. Zo kan een nieuwe telefoon of een herinstallatie nooit een bestaand profiel overschrijven.
- **Wanneer:** bij app-start, bij terugkeer naar de voorgrond, na een lokale wijziging (met 2 seconden vertraging) en wanneer `NWPathMonitor` meldt dat het netwerk terug is.
- **Uitloggen:** eerst nog een push proberen. Lukt dat niet (offline) en zijn er onverstuurde wijzigingen, dan waarschuwen; daarna de lokale data van die gebruiker wissen.
- **Een push die de server weigert** (bijvoorbeeld een grenswaarde) mag niet eindeloos opnieuw proberen. De app gebruikt dezelfde grenzen als de database (`FitlingCore/Limits.swift` ↔ de `check`-regels in SQL, bewaakt door een test aan beide kanten). Lukt het toch niet, dan krijgt de gebruiker een melding en blijft de lokale versie staan.
- Vanaf fase 2: per tabel een pull-cursor op `synced_at` met 5 minuten overlap. De overlap vangt transacties op die later committen. Dubbel binnenhalen is onschuldig omdat lokaal op `id` wordt bijgewerkt.

### 4.6 Inloggen, account en toestemming

| Flow | Hoe |
|---|---|
| Sign in with Apple | `ASAuthorizationAppleIDProvider`. Willekeurige nonce, SHA-256 (CryptoKit) in het verzoek, ruwe nonce naar `supabase.auth.signInWithIdToken(credentials: OpenIDConnectCredentials(provider: .apple, idToken:, nonce:))` |
| Google | `supabase.auth.signInWithOAuth(provider: .google, redirectTo: fitling://auth-callback)` met `ASWebAuthenticationSession` |
| E-mail registreren | `supabase.auth.signUp(email:password:redirectTo:)` → scherm "Bevestig je e-mail". De verificatielink opent `fitling://auth-callback` → `supabase.auth.session(from: url)` via `.onOpenURL` |
| E-mail inloggen | `supabase.auth.signIn(email:password:)`. Nog niet geverifieerd → scherm "Bevestig je e-mail" met "Opnieuw sturen" |
| Wachtwoord vergeten | De app roept zelf `supabase.auth.resetPasswordForEmail(email, redirectTo: fitling://reset-password)` aan (PKCE, de code-verifier blijft op het toestel). Altijd dezelfde melding, of het adres bestaat of niet: "Als er een account met dit adres is, krijg je een mail. Log je in met Apple of Google? Gebruik dan die knop." Daaronder "Account aanmaken". Een rate-limitfout van Supabase → "Te veel pogingen, probeer het later opnieuw". De link opent de app → `session(from:)` → scherm "Nieuw wachtwoord" → `supabase.auth.update(user: UserAttributes(password:))`. Werkt de link niet (geopend op een ander toestel of na herinstallatie) → "Deze link werkt alleen op het toestel waar je hem hebt aangevraagd. Vraag een nieuwe aan." |
| Toestemming | Eerste onboardingstap, vóór er gezondheidsgegevens worden ingevoerd (AVG art. 9: lengte, gewicht, geslacht en een dieetdoel zijn gezondheidsgegevens). Korte tekst wat er wordt opgeslagen en waarom, en de knop "Akkoord". Opgeslagen als `health_consent_at` + `health_consent_version`. Toestemming intrekken = account verwijderen. De link naar de privacyverklaring komt erbij zodra die bestaat |
| Leeftijd | Bij een geboortedatum onder de 18: "Fitling is voor mensen vanaf 18 jaar." met de knop "Account verwijderen", die de normale verwijderflow start |
| Account verwijderen | AccountView → bevestiging → bij Apple-account eerst opnieuw via Apple om een verse `authorizationCode` → Edge Function `delete-account` (§5.3) → lokaal uitloggen en SwiftData wissen |

URL-scheme `fitling` (custom scheme). Universal links vragen een eigen domein met `apple-app-site-association`; dat is pas nodig als e-mailclients het custom scheme blokkeren.

De rate limiting uit PROMPT.md (max 5 per uur via een Edge Function) was er om de check "bestaat dit account?" te beschermen. Met de neutrale melding bestaat die check niet meer. Supabase Auth begrenst het versturen van reset-mails zelf, dus een eigen Edge Function en tabel zouden niets toevoegen.

### 4.7 Rekenregels (FitlingCore)

Vaste formules (PROMPT.md "nooit verzonnen getallen"). Waar een getal een keuze is, staat dat erbij.

- **Leeftijd** uit `birthDate`, berekend met de vaste UTC-kalender (§5.4).
- **BMR (Mifflin-St Jeor):** `10 × kg + 6,25 × cm − 5 × leeftijd + s`, met `s = +5` (man), `−161` (vrouw), `−78` (anders: het gemiddelde van beide; *mijn keuze*).
- **TDEE = BMR × activiteitsfactor:** zittend 1,2 · licht 1,375 · matig 1,55 · actief 1,725 · zeer actief 1,9 (de standaardfactoren).
- **kcal-doel = TDEE × doelfactor**, afgerond op 10: afvallen 0,80 · spieropbouw 1,10 · onderhoud 1,00 · recomp 0,95 (*mijn keuze, binnen gangbare bereiken*).
- **Eiwit (g) = kg × factor** binnen 1,6–2,2: afvallen 2,0 · spieropbouw 1,8 · onderhoud 1,6 · recomp 2,2 (*mijn keuze*).
- **Vet = 25 % van kcal / 9** (*mijn keuze*). **Koolhydraten = rest / 4**, nooit onder 0.
- **Waarschuwing** (geen blokkade) als het kcal-doel onder 1500 (man) of 1200 (vrouw/anders) komt.
- **Grenzen** (`Limits.swift`, gelijk aan de SQL-checks). Invoer: lengte 100–250 cm, gewicht 30–350 kg, leeftijd 18+. Doelen: kcal 1–20 000, eiwit 0–1000 g, koolhydraten 0–5000 g, vet 0–2000 g. Dit zijn alleen grenzen voor onmogelijke waarden; elke berekening binnen de invoergrenzen valt erbinnen (hoogste berekende kcal ≈ 10 400).
- **Handmatig aanpassen:** de gebruiker kan kcal en elke macro overschrijven → `targetsAreManual = true`. Verandert daarna het profiel (EditProfileView), dan vraagt de app "Doelen opnieuw berekenen?" in plaats van ze stilletjes te overschrijven.
- **Opslag altijd metrisch** (kg, cm, kcal). Weergave via `Measurement` + `Locale`: kg/lb, cm/ft-in, kcal/kJ.

### 4.8 Vormgeving fase 1

- Eigen vast kleurpalet als named colors in `Assets.xcassets`, met een licht- en donkervariant. Geen gradients, geen glassmorphism.
- SF Symbols, Dynamic Type-tekststijlen, spacing op een 4-pt-raster (`Spacing.swift`: 4, 8, 12, 16, 24, 32).
- Het palet en de typografie worden aan het begin van de bouw vastgelegd met de `impeccable`-skill (een DESIGN.md) en daarna overal gebruikt.
- Toegankelijkheid: VoiceOver-labels via String Catalog, minimaal 44 pt tikvlakken, getest in donkere modus en met de grootste Dynamic Type-stand (UI-test).

### 4.9 Lokalisatie

- `Localizable.xcstrings` met ontwikkeltaal `nl`, plus `en` en `de`.
- Semantische sleutels (`onboarding.height.title`), zodat een tekstwijziging geen sleutel breekt en een script kan controleren of alles vertaald is.
- `scripts/check-strings.mjs` (Node, geen dependencies) faalt in de CI als een sleutel in de code geen `nl`/`en`/`de`-waarde heeft, of als `Text("…")` een letterlijke zin met spaties bevat.
- `FitlingCore` bevat geen UI-teksten.
- De e-mails van Supabase (verificatie, reset) zijn standaard in één taal. Meertalige e-mails horen bij de eigen e-mailserver, vóór TestFlight (§7).

## 5. Fase 1 in code

### 5.1 FitlingCore

```swift
public enum Sex: String, Sendable, CaseIterable, Codable { case male, female, other }

public enum ActivityLevel: String, Sendable, CaseIterable, Codable {
    case sedentary, light, moderate, active
    case veryActive = "very_active"
}

public enum Goal: String, Sendable, CaseIterable, Codable {
    case lose
    case buildMuscle = "build_muscle"
    case maintain, recomp
}

public struct BodyProfile: Sendable, Equatable {
    public var birthDate: Date
    public var sex: Sex
    public var heightCm: Double
    public var weightKg: Double
    public var activityLevel: ActivityLevel
    public var goal: Goal
}

public struct NutritionTargets: Sendable, Equatable, Codable {
    public var kcal: Int
    public var proteinG: Int
    public var carbsG: Int
    public var fatG: Int
}

public struct EnergyCalculation: Sendable, Equatable {
    public let bmr: Double
    public let tdee: Double
    public let targets: NutritionTargets
    public let isBelowSafeMinimum: Bool
}

public func calculateEnergy(for profile: BodyProfile, on date: Date, calendar: Calendar) -> EnergyCalculation
public func age(birthDate: Date, on date: Date, calendar: Calendar) -> Int
```

De rawValues van de enums zijn precies de `check`-waarden in SQL. Er is één bron, en een pgTAP-test plus een Swift-test bewaken dat ze gelijk blijven.

Tests (`FitlingCoreTests`, Swift Testing): BMR voor man/vrouw/anders met handberekende waarden, elke activiteitsfactor, elk doel, afronding, koolhydraten nooit negatief, leeftijd rond de verjaardag, de 18-grens, de grens van de waarschuwing, en dat de uitersten van de invoer binnen `Limits` vallen.

### 5.2 Supabase-migratie

`supabase/migrations/20261118120000_profiles.sql`

```sql
create schema if not exists private;

-- Laatste wijziging wint op updated_at (klok van de client).
-- synced_at is de klok van de server en dient vanaf fase 2 als pull-cursor.
create function private.apply_sync_rules()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and new.updated_at < old.updated_at then
    return null;
  end if;
  new.synced_at := now();
  return new;
end;
$$;

create table public.profiles (
  id                     uuid primary key references auth.users (id) on delete cascade,
  health_consent_at      timestamptz not null,
  health_consent_version integer not null check (health_consent_version > 0),
  -- Vergelijken met current_date wordt alleen gecontroleerd bij insert/update;
  -- dat volstaat omdat iemand alleen ouder wordt.
  birth_date             date not null check (
                           birth_date >= date '1900-01-01'
                           and birth_date <= (current_date - interval '18 years')::date
                         ),
  sex                    text not null check (sex in ('male', 'female', 'other')),
  height_cm              numeric(4,1) not null check (height_cm between 100 and 250),
  weight_kg              numeric(4,1) not null check (weight_kg between 30 and 350),
  activity_level         text not null check (activity_level in ('sedentary', 'light', 'moderate', 'active', 'very_active')),
  goal                   text not null check (goal in ('lose', 'build_muscle', 'maintain', 'recomp')),
  kcal_target            integer not null check (kcal_target between 1 and 20000),
  protein_target_g       integer not null check (protein_target_g between 0 and 1000),
  carbs_target_g         integer not null check (carbs_target_g between 0 and 5000),
  fat_target_g           integer not null check (fat_target_g between 0 and 2000),
  targets_are_manual     boolean not null default false,
  updated_at             timestamptz not null,
  synced_at              timestamptz not null default now()
);

create trigger profiles_apply_sync_rules
  before insert or update on public.profiles
  for each row execute function private.apply_sync_rules();

alter table public.profiles enable row level security;

create policy "profiles: eigen rij lezen" on public.profiles
  for select to authenticated
  using ((select auth.uid()) = id);

create policy "profiles: eigen rij aanmaken" on public.profiles
  for insert to authenticated
  with check ((select auth.uid()) = id);

create policy "profiles: eigen rij wijzigen" on public.profiles
  for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);
-- Geen delete-policy: een profiel verdwijnt alleen via account verwijderen (cascade).
```

pgTAP-tests (`supabase/tests/`): gebruiker A kan het profiel van B niet lezen, aanmaken of wijzigen; `anon` ziet niets; een oudere `updated_at` overschrijft niets; `synced_at` wordt door de server gezet; een geboortedatum onder de 18 wordt geweigerd; de enum-waarden komen overeen met die in FitlingCore.

### 5.3 Edge Function `delete-account` (TypeScript, Deno)

Gedeployed met `verify_jwt = false`. De controle van de JWT door de gateway werkt volgens de Supabase-docs alleen met de oude JWT-sleutels, niet met publishable/secret keys. De functie controleert het token daarom zelf.

1. Token uit de `Authorization`-header → `auth.getUser(token)` met de service-client. Geen geldige gebruiker → 401.
2. Heeft het account een Apple-identiteit: met de meegestuurde `authorizationCode` een token ophalen bij `https://appleid.apple.com/auth/token` en dat intrekken via `https://appleid.apple.com/auth/revoke`. Apple eist dit bij accountverwijdering. Het `client_secret` is een ES256-JWT, ondertekend met Web Crypto (geen library). Gegevens: `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`, `APPLE_CLIENT_ID` als secrets van de functie. Die bestaan pas met het Apple Developer Program; tot dan wordt deze stap alleen getest met een nagebootst Apple-antwoord.
3. `auth.admin.deleteUser(userId)` → `profiles` verdwijnt via de cascade. Vanaf fase 2 hier ook de Storage-bestanden van de gebruiker verwijderen.
4. Mislukt het intrekken bij Apple, dan wordt het account toch verwijderd en de fout gelogd (*mijn keuze*: het verwijderverzoek van de gebruiker gaat voor).

Tests: `deno test` met nagebootste Supabase- en Apple-antwoorden: geen token, ongeldig token, e-mailaccount, Apple-account, Apple-fout.

### 5.4 SwiftData-modellen fase 1

```swift
enum FitlingSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [UserProfile.self] }

    @Model
    final class UserProfile {
        @Attribute(.unique) var id: UUID      // = Supabase auth user id
        var healthConsentAt: Date
        var healthConsentVersion: Int
        var birthDate: Date                   // middernacht UTC, zie BirthDateCalendar
        var sexRaw: String
        var heightCm: Double
        var weightKg: Double
        var activityLevelRaw: String
        var goalRaw: String
        var kcalTarget: Int
        var proteinTargetG: Int
        var carbsTargetG: Int
        var fatTargetG: Int
        var targetsAreManual: Bool
        var updatedAt: Date
        var needsPush: Bool
    }
}

typealias UserProfile = FitlingSchemaV1.UserProfile

enum FitlingMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [FitlingSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
```

- Enums worden als `String` opgeslagen, met getypeerde computed properties (`sex`, `activityLevel`, `goal`). Zo blijven `#Predicate`-queries werken.
- Versiebeheer zit erin vanaf V1, zodat latere fases kunnen migreren zonder dat iemand data verliest.
- **Geboortedatum:** één vaste kalender (`BirthDateCalendar`: gregoriaans, tijdzone UTC) voor de `DatePicker` (via `.environment(\.calendar, …)` en `.environment(\.timeZone, …)`), de leeftijdsberekening en de conversie naar `yyyy-MM-dd`. Zo schuift de datum niet een dag op in tijdzones ten westen van UTC.
- `ProfileRecord` (Codable, `snake_case`) vertaalt tussen SwiftData en de `profiles`-rij.

### 5.5 Schermen fase 1

```
Start ─► Welkom ─► [Apple] [Google] [E-mail] ─► (e-mail) Registreren/Inloggen ─► Bevestig je e-mail
                                                       └─► Wachtwoord vergeten ─► neutrale melding / Account aanmaken
Ingelogd, pull: geen profiel ─► Onboarding: toestemming · geboortedatum (18+) · geslacht · lengte · gewicht · activiteit · doel ─► Je dagdoel
Ingelogd, offline, geen lokaal profiel ─► "Verbind met internet om je profiel op te halen"
Ingelogd met profiel ─► Dagdoel (kcal + macro's, hoe het berekend is)
                          ├─► Profiel bewerken ─► "Doelen opnieuw berekenen?" (als ze handmatig zijn)
                          ├─► Doelen aanpassen
                          └─► Account (uitloggen, verwijderen)
```

Het dagdoel-scherm is in fase 1 het startscherm. In fase 2 komt daar het dagoverzicht met de kcal-ring voor in de plaats.

## 6. Tests en CI

`.github/workflows/ci.yml`, ingericht op een privé-repo met beperkte Mac-minuten:

| Job | Runner | Wanneer | Doet |
|---|---|---|---|
| `core` | ubuntu | elke push en PR | `swift test` in `Packages/FitlingCore` |
| `strings` | ubuntu | elke push en PR | `node scripts/check-strings.mjs` |
| `backend` | ubuntu | elke push en PR | Supabase CLI: `supabase db start`, `supabase test db`; `deno test` voor de functie |
| `ios` | macos | push naar `main` en handmatig starten; pas na groene Linux-jobs | `xcodegen generate` → `xcodebuild test -scheme Fitling -destination 'platform=iOS Simulator,name=iPhone 16 Pro'` → `.xcresult` en screenshots als artefact |

- **Zuinig met Mac-minuten:** werk gebeurt op een branch, waar alleen de goedkope Linux-jobs draaien. Een afgerond stuk gaat naar `main` en krijgt één Mac-run. Verder: `concurrency: cancel-in-progress`, `timeout-minutes: 30` op de Mac-job, en een cache voor de SPM-pakketten (sleutel: hash van `project.yml`).
- **UI-test:** loopt door welkom → onboarding → dagdoel en bewaart een screenshot per scherm (`XCTAttachment`), ook in donkere modus en met de grootste tekstgrootte. Zo zie je de schermen zonder Mac. De Mac van GitHub kan niet echt inloggen. Daarom start de UI-test de app met het argument `--ui-testing`: de app gebruikt dan de nep-`AuthProviding` (ingelogd, geen server) en een SwiftData-store in het geheugen. Die code staat in `Fitling/UITesting/` en wordt alleen in DEBUG-builds meegecompileerd. Het is testgereedschap, geen nepdata in de app.
- CLAUDE.md noemt `xcodebuild … build`; de CI doet `test`, en dat is bouwen plus testen.
- "Klaar" betekent: alle vier de jobs groen op `main`.

## 7. Wat jij moet regelen

Dit kan ik niet voor je doen (accounts aanmaken, betalen en inloggen doe je zelf).

**Voor de bouw van fase 1**
1. **GitHub:** een privé-repo, de GitHub CLI (`gh`) op deze pc met `gh auth login` zodat ik CI-resultaten kan lezen, en een uitgavenlimiet voor Actions (bijvoorbeeld $0 of een vast bedrag) zodat het nooit ongemerkt geld kost. Pushen doe ik alleen als jij dat vraagt.
2. **Supabase-project** (gratis tier) in een **EU-regio** (bijvoorbeeld Frankfurt). De regio is later niet te wijzigen. Daarna: de host en de publishable key als GitHub-secrets, "Confirm email" aan, en de redirect-URL's `fitling://auth-callback` en `fitling://reset-password`. Let op: een gratis project pauzeert na een week zonder gebruik.
3. **Google Cloud OAuth-client** voor de Google-login via Supabase.
4. **Migraties uitrollen** naar je Supabase-project met `supabase db push`. Dat commando draai jij (ik geef het). Geen automatische uitrol naar productie.

**Vóór TestFlight (later)**
5. **Apple Developer Program** (€99/jaar): Sign in with Apple, de sleutel voor het intrekken van tokens, code signing en TestFlight.
6. **Eigen e-mailserver (SMTP) en een domein.** De ingebouwde mail van Supabase stuurt alleen naar leden van je Supabase-team, ongeveer 2 per uur. Dan ook de e-mails in nl/en/de.
7. **Privacyverklaring** (link in de toestemmingsstap) en een apart productieproject naast het ontwikkelproject.

## 8. Te verifiëren tijdens het bouwen

Ik heb ze nagekeken waar dat kon. Deze punten controleer ik bij de eerste build in de officiële docs of met een echte aanroep, en ik pas het ontwerp aan als ze anders blijken:

- Exacte handtekeningen in supabase-swift 2.x van `signUp(… redirectTo:)`, `resetPasswordForEmail(_:redirectTo:)`, `update(user:)` en de optie `emitLocalSessionAsInitialSession`. Gecontroleerd zijn: `signInWithIdToken` met `OpenIDConnectCredentials`, `signInWithOAuth` met `ASWebAuthenticationSession` en `session(from:)`.
- Of de JWT-controle door de gateway met de nieuwe Supabase-sleutels inderdaad niet werkt (het ontwerp werkt in beide gevallen, want de functie controleert zelf).
- De naam van de service-sleutel als omgevingsvariabele in Edge Functions (`SUPABASE_SERVICE_ROLE_KEY` of een nieuwe secret key).
- De syntax voor exacte pakketversies in XcodeGen (`project.yml`).
- Welke Xcode-versie en welke simulator ("iPhone 16 Pro") op de macOS-runner beschikbaar zijn.
- Of een App Group (nodig voor de widget in fase 3) op de simulator werkt zonder developer-team. Zo ja, dan staat de SwiftData-store vanaf fase 1 in de App Group. Zo nee, dan wordt de store bij de TestFlight-opzet eenmalig verplaatst.

## 9. Mijn keuzes

Dit heb ik zelf beslist. Je kunt elke keuze terugdraaien:

- De publishable key van Supabase staat wel in de app (via xcconfig). Die is bedoeld om openbaar te zijn en wordt beschermd door RLS. "Geen API-keys in de app" lees ik als: geen geheime sleutels. De service-sleutel, Apple-sleutels en betaalde API's staan alleen in Edge Functions.
- Eerst een account, dan de onboarding. Het profiel hoort meteen bij een gebruiker.
- Een toestemmingsstap voor gezondheidsgegevens (AVG art. 9) als eerste onboardingstap, met tijdstip en versie in het profiel.
- Geboortedatum in plaats van leeftijd, zodat de leeftijd zichzelf bijwerkt. Onder de 18: uitleg en account verwijderen.
- Formulekeuzes in §4.7 (geslacht "anders", doelfactoren, eiwit per doel, 25 % vet, waarschuwingsgrens) en de grenzen in `Limits`.
- Geen eigen rate limiting meer bij wachtwoord vergeten (§4.6): Supabase begrenst zelf.
- Google via de OAuth-flow van Supabase, zonder Google SDK.
- Een custom URL-scheme in plaats van universal links.
- Volledige SQL en Swift alleen voor fase 1 (§4.4).
- Sync op de main context; nog geen algemene sync-engine (komt in fase 2).
- Profiel bewerken hoort bij fase 1.
- Bij account verwijderen gaat het verwijderen door, ook als het intrekken bij Apple mislukt.
- Een DEBUG-only startargument voor de UI-test (§6).
- Logica-tests in `FitlingCoreTests` (los pakket), app-tests in `FitlingTests`.
- Eén Supabase-project tot TestFlight.

## 10. Voorgestelde wijzigingen in CLAUDE.md

Doorgevoerd op 2026-11-18:

- **"Bouw met: xcodebuild …"** wordt: "Bouwen en testen gebeurt in GitHub Actions (geen Mac). Klaar = alle CI-jobs groen op main."
- **"Elke nieuwe feature: unit tests in FitlingTests"** wordt: "… unit tests in FitlingTests (app) of FitlingCoreTests (rekenregels)."
- **Nieuwe regel:** "Testgereedschap voor de UI-test mag in `Fitling/UITesting/`, alleen in DEBUG-builds."
- **Skills-sectie terug** (die viel weg toen CLAUDE.md werd vervangen): de vier project-skills in `.claude/skills/` worden bij al het werk gebruikt (`unforget` voor uitgesteld werk, `bug-echo` na elke bugfix, `prompter` bij onduidelijke opdrachten, `skill-reviewer` bij nieuwe of gewijzigde skills), naast de andere geïnstalleerde skills waar ze passen.

## 11. Beslissingen van jou (2026-11-18)

- Bouwen op een Mac van GitHub (aanpak A).
- TestFlight nog niet in fase 1, maar later.
- Privé GitHub-repo.
- Wachtwoord vergeten: altijd een neutrale melding.
- Minimumleeftijd 18 jaar.

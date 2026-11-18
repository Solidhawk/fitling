# Fitling – architectuur

Dit document legt vast hoe de app in elkaar zit en waarom. Het hoort bij `PROMPT.md` (wat de app moet doen), `supabase/schema.sql` (de database), `Packages/FitlingCore` (de rekenregels) en `docs/TASKS.md` (wat er nog gebouwd wordt). Waar dit document en het oudere ontwerp in `docs/superpowers/specs/` verschillen, geldt dit document.

Status: het fundament staat op branch `fundament`. Bewezen in CI: de rekenregels (Linux), het schema met RLS (Linux), de gelijkheid tussen modellen en schema (Linux) en de lokale database met alle modellen (Mac-simulator). Er zijn nog geen schermen, geen sync-code in de app en geen Edge Functions behalve `delete-account`.

## 1. Lagen

| Laag | Map | Wat hoort hier | Mag afhangen van |
|---|---|---|---|
| Core (regels) | `Packages/FitlingCore` | Rekenregels en waardetypes zonder UI, opslag of netwerk: `NutritionEngine`, `CreatureEngine`, `ProgressionEngine`, `WeekMenuPlanner`, `FoodMath`, `ShoppingListBuilder`, `OfferMatcher`, `SyncRules`, `Day`, `Barcode`, `LocalizedText`, `Limits` | alleen Foundation |
| Core (modellen) | `Fitling/Core/Models` | De SwiftData-modellen, één per tabel, en de omzetting naar de types van FitlingCore | FitlingCore, SwiftData |
| Data | `Fitling/Data` | Sync (`SyncEngine`, per tabel een beschrijving en een record-type), opvragen van data voor schermen, de HealthKit-cache | Core, Services |
| Services | `Fitling/Services` | Alles wat met de buitenwereld praat: `AuthService`, de Supabase-client, `ProductLookup`, `HealthKitService`, `NotificationService`, `NetworkMonitor` | Core |
| Features | `Fitling/Features/<Naam>` | Per onderdeel de schermen (`View`) en hun `@Observable @MainActor` ViewModels | Core, Data, Services, DesignSystem |
| App | `Fitling/App` | Startpunt, de keuze welk scherm bovenaan staat, en het aanmaken en doorgeven van services | alles |
| DesignSystem | `Fitling/DesignSystem` | Kleuren, afstanden, knoppen, de tekeningen van de wezentjes | SwiftUI |
| Backend | `supabase/` | `schema.sql`, pgTAP-tests, Edge Functions | – |

Regels:

- **FitlingCore kent geen SwiftData, SwiftUI of Supabase.** Daardoor draaien de tests op een gratis Linux-runner en kost een rekenfout geen Mac-minuten.
- **Views bevatten geen logica.** Een View leest zijn ViewModel. Een ViewModel rekent niet zelf maar roept FitlingCore aan.
- **Alleen `Services` en `Data/Sync` importeren `Supabase`.** Features kennen de backend niet.
- **Eén protocol per service die in tests vervangen moet worden** (`AuthProviding`, `ProductLookingUp`, `HealthReading`). Verder geen protocollen zonder tweede implementatie.
- **Doorgeven via SwiftUI `.environment`** vanuit `FitlingApp`. Geen singletons.
- **Dagen zijn `Day`, geen `Date`.** Een log, een training, een geboortedag en een menu horen bij een kalenderdag. Lokaal en in Postgres staat die als `"2026-11-18"`. Alleen echte tijdstippen (`updated_at`, `started_at`) zijn `Date`/`timestamptz`.

## 2. Datamodel

`supabase/schema.sql` is de bron. Lokaal heeft elke tabel die de app gebruikt een SwiftData-model met dezelfde kolommen; `scripts/check-models.mjs` controleert in CI namen, soort waarde en optioneel/verplicht.

| Soort | Tabellen | Wie leest | Wie schrijft |
|---|---|---|---|
| Privé | `profiles`, `target_history`, `food_entries`, `water_entries`, `favorite_products`, `creatures`, `exercise_settings`, `workout_sessions`, `workout_sets`, `body_measurements`, `menu_preferences`, `excluded_ingredients`, `meal_plan_entries`, `favorite_supermarkets` | alleen de eigenaar | alleen de eigenaar |
| Gedeeld + eigen | `products`, `recipes`, `recipe_ingredients`, `exercises`, `programs`, `program_days`, `program_exercises` | iedereen de gedeelde rijen (`owner_id is null`), de eigenaar de eigen rijen | de backend de gedeelde rijen, de eigenaar de eigen rijen |
| Gedeelde lijst | `shopping_lists`, `shopping_list_members`, `shopping_items` | leden van de lijst | leden van de lijst |
| Alleen lezen | `supermarkets`, `offers` | iedereen die is ingelogd | alleen de backend |
| Alleen server | `product_submissions`, `shopping_list_invites`, `private.rate_limits` | – | Edge Functions en databasefuncties |
| Alleen toestel | `ProgressPhoto`, `DayActivity`, `SyncCursor` | – | – |

Keuzes in de modellen (ook als commentaar in `FitlingSchemaV1.swift`):

- Verwijzingen zijn een id, geen `@Relationship`: een kind kan eerder van de server komen dan zijn ouder.
- Enums staan als tekst: `#Predicate` kan erop filteren en een onbekende waarde van een nieuwere app-versie laat een oudere niet crashen. De omzetting naar het enum geeft dan `nil`.
- Tekst per taal (`name`, `title`, `instructions`) is `jsonb` op de server en JSON in `Data` lokaal, met `LocalizedText` als type. Interfaceteksten staan in de String Catalog; inhoud uit de database niet.
- Een voedingslog bewaart naam en waarden op het moment van loggen. Een bijgewerkt product verandert oude dagen niet.
- Het wezentje bewaart alleen wat niet uit de logs te herleiden is (vorm, XP, laatst verwerkte dag). De toestand rekent `CreatureEngine` steeds opnieuw uit.
- `target_history` bewaart de doelen per periode, zodat een dag wordt vergeleken met het doel dat toen gold.
- Voortgangsfoto's en trainingsenergie uit HealthKit verlaten het toestel niet.

## 3. Offline-first sync

SwiftData is op het toestel de waarheid. De app werkt volledig zonder internet; sync haalt later in.

De beslissingen van sync staan als pure functies in `SyncRules` (FitlingCore) en zijn op Linux getest: wat een pull met een rij doet, waar een pull begint, hoe de cursor opschuift en wanneer de push-vlag weg mag. De `SyncEngine` in de app (TASKS 1.3) voert ze uit en beslist zelf niets.

### 3.1 Per rij

- Elke wijziging zet `updatedAt = nu` en `needsPush = true`, en slaat de context direct op (`context.save()`), niet via autosave.
- Verwijderen is `deletedAt = nu` zetten. De rij blijft lokaal staan tot de server hem heeft; schermen filteren op `deletedAt == nil`.

### 3.2 Push

1. Per tabel de rijen met `needsPush` ophalen, in de volgorde van §3.5 (ouders vóór kinderen).
2. In blokken van 200 naar Supabase met `upsert` op de sleutel.
3. Na succes `needsPush` alleen wissen als `updatedAt` nog gelijk is aan wat verstuurd is. Een wijziging tijdens de push blijft zo staan voor de volgende ronde.
4. Is de rij verstuurd met `deletedAt`, dan wordt hij daarna lokaal echt verwijderd.

### 3.3 Conflicten: laatste wijziging wint

- De trigger `private.apply_sync_rules` negeert een update met een oudere `updated_at` dan wat er staat. De server geeft dan geen rij terug; de client haalt bij de volgende pull de nieuwere versie op.
- Een `updated_at` meer dan vijf minuten in de toekomst zet de server terug naar zijn eigen tijd. Een toestel met een verkeerde klok kan zo niet blijven winnen.
- Samenvoegen per veld gebeurt niet: het is één gebruiker met meestal één toestel, en een log is een kleine rij.
- Waar twee toestellen offline hetzelfde zouden kunnen aanmaken, is het model zo gekozen dat het optelt in plaats van botst: water als losse rijen, favorieten en doelperiodes zonder unieke eis (de lezer neemt de nieuwste).

### 3.4 Pull

- Per tabel een cursor (`SyncCursor`): de hoogste `synced_at` die is gezien.
- Ophalen waar `synced_at > cursor − 5 minuten`, gesorteerd op `synced_at, id`, per 500 rijen. De overlap vangt transacties op die later committen; dubbel binnenhalen is onschuldig.
- Toepassen: lokaal opzoeken op id. Bestaat de rij niet, dan toevoegen. Bestaat hij wel en heeft hij `needsPush` met een nieuwere `updatedAt`, dan blijft de lokale versie staan. Anders wint de server. Een rij met `deleted_at` wordt lokaal verwijderd.
- Nieuw toestel of herinstallatie: eerst alles ophalen, dan pas data tonen. De onboarding start alleen als een geslaagde pull bevestigt dat er geen profiel is.
- Is de cursor ouder dan 90 dagen, dan wordt de tabel lokaal geleegd en opnieuw opgehaald. De server ruimt verwijdermarkeringen na 90 dagen op (taak in fase 7); een ouder toestel zou die anders missen.

### 3.5 Volgorde en momenten

Push-volgorde: `profiles`, `target_history`, `products`, `recipes`, `recipe_ingredients`, `food_entries`, `water_entries`, `favorite_products`, `creatures`, `exercises`, `programs`, `program_days`, `program_exercises`, `exercise_settings`, `workout_sessions`, `workout_sets`, `body_measurements`, `menu_preferences`, `excluded_ingredients`, `meal_plan_entries`, `shopping_lists`, `shopping_list_members`, `shopping_items`, `favorite_supermarkets`.

Sync draait bij app-start, bij terugkeer naar de voorgrond, twee seconden na een lokale wijziging en wanneer het netwerk terugkomt. Er loopt nooit meer dan één ronde tegelijk; een verzoek tijdens een ronde start er daarna één.

### 3.6 Wat de server weigert

Een rij die de server blijft weigeren (grenswaarde, onbekende verwijzing) mag de rest niet blokkeren. De push gaat door met de volgende rij, de geweigerde rij houdt `needsPush`, en de gebruiker ziet één rustige melding ("Niet alles is opgeslagen op de server"). De app gebruikt dezelfde grenzen als de database (`Limits` ↔ de `check`-regels), zodat dit alleen bij een fout van ons gebeurt.

### 3.7 Uitloggen en account verwijderen

Uitloggen: eerst pushen. Lukt dat niet en staat er nog iets klaar, dan waarschuwen. Daarna alle lokale data wissen, ook als het uitloggen zelf offline mislukt. Account verwijderen: Edge Function `delete-account`, daarna lokaal wissen. Alle tabellen hangen met `on delete cascade` aan `auth.users`.

### 3.8 Gedeelde boodschappenlijst

- Dezelfde sync en dezelfde regel "laatste wijziging wint", per item. Twee huisgenoten die hetzelfde item afvinken geeft hetzelfde resultaat; twee die het verschillend bewerken: de laatste wint.
- Realtime: de app luistert op wijzigingen van `shopping_items` voor de lijsten waar de gebruiker lid van is, en start bij een melding een pull van die tabel. De inhoud van de melding wordt niet zelf toegepast: zo is er één plek die data binnenhaalt.
- Lid worden gaat alleen met een uitnodigingscode (`create_shopping_list_invite`, `join_shopping_list`). De code is zeven dagen geldig; de database bewaart alleen de hash.
- Een lijst kan offline worden aangemaakt: de maker voegt zichzelf toe als eigenaar. Gaat de eigenaar weg, dan wordt het langst aanwezige lid eigenaar. Een lijst zonder leden verdwijnt.
- Leden zien van elkaar alleen de naam die ze bij het lid worden opgeven. Profielen blijven privé.

### 3.9 Dubbele producten voorkomen

- De gedeelde cache heeft hoogstens één rij per barcode (`products_shared_gtin`) en per bronrecord (`products_shared_source`).
- De sleutel is de genormaliseerde barcode uit `Barcode.normalized`: EAN-8 als 8 cijfers, EAN-13 als 13 cijfers, UPC-A als 13 cijfers met een 0 ervoor, en alleen met een geldig controlecijfer.
- Alleen de Edge Function `lookup-product` schrijft in de gedeelde cache, met `insert ... on conflict (gtin) do update`. Twee gebruikers die tegelijk dezelfde barcode scannen, eindigen op dezelfde rij.
- Eigen producten zonder barcode zijn privé (`owner_id`) en kunnen dus nooit met de cache botsen.

## 4. Inloggen en account

| Flow | Hoe |
|---|---|
| Sign in with Apple | `ASAuthorizationAppleIDProvider` met een willekeurige nonce (SHA-256 in het verzoek, ruwe nonce naar `signInWithIdToken`) |
| Google | `signInWithOAuth(provider: .google, redirectTo: fitling://auth-callback)` via `ASWebAuthenticationSession`, zonder Google SDK |
| E-mail registreren | `signUp(email:password:redirectTo:)` → scherm "Bevestig je e-mail" → de link opent `fitling://auth-callback` → `session(from:)` |
| E-mail inloggen | `signIn(email:password:)`; niet bevestigd → scherm "Bevestig je e-mail" met "Opnieuw sturen" |
| Wachtwoord vergeten | `resetPasswordForEmail`, altijd dezelfde melding: "Als er een account met dit adres is, krijg je een mail." Daaronder "Account aanmaken" (D-03) |
| Account verwijderen | Bevestigen, bij een Apple-account opnieuw via Apple voor een verse code, dan Edge Function `delete-account` (trekt het Apple-token in en verwijdert de gebruiker), daarna lokaal wissen |
| Toestemming | Eerste onboardingstap, vóór er gezondheidsgegevens worden ingevoerd; opgeslagen als tijdstip en versie |
| Leeftijd | Onder de 18: uitleg en "Account verwijderen" |

De methodes van supabase-swift 2.55.7 die hier genoemd worden, zijn bij de eerdere bouw van fase 1 in de broncode van die versie nagekeken; de werkende code staat als naslag op branch `fase-1`.

**De check "e-mail niet bekend" uit PROMPT.md wordt niet gebouwd** (beslissing van de gebruiker, D-03). Er is dus ook geen Edge Function met rate limiting voor het resetten: Supabase Auth begrenst het versturen van mails zelf. De rate limiting uit PROMPT.md is wel gebouwd waar hij geld of een externe bron beschermt: `lookup-product` en `submit-product` tellen per gebruiker per uur in `private.rate_limits`.

## 5. Barcode-pipeline

```
scan → Barcode.normalized → 1. lokaal (SwiftData)
                            2. Edge Function lookup-product
                                 a. gedeelde cache (products)
                                 b. Open Food Facts
                                 c. betaalde bron (uit tot er een contract is)
                            3. niet gevonden → zelf toevoegen
```

1. **Lokaal.** `Product` op `gtin`. Gevonden en jonger dan 30 dagen (`fetchedAt`): direct gebruiken. Werkt offline.
2. **`lookup-product`** (Edge Function, alleen voor ingelogde gebruikers, 60 aanroepen per gebruiker per uur):
   - a. Rij in `products` met deze `gtin` en `fetched_at` jonger dan 30 dagen → teruggeven.
   - b. Open Food Facts: `GET https://world.openfoodfacts.org/api/v2/product/{barcode}?fields=…` met `User-Agent: Fitling/1.0 (contact-e-mail)`. Bij 503 of een time-out: drie pogingen met oplopende wachttijd (1, 2, 4 seconden). Gevonden → normaliseren (§5.1), in de cache zetten, teruggeven.
   - c. Betaalde bron (FatSecret of Nutritionix): dezelfde vorm, sleutel alleen in de functie. Staat uit tot er een contract en een budget is (RISKS R-04).
   - Niets gevonden → `404 not_found`. De functie bewaart geen "niet gevonden", zodat een product dat morgen in Open Food Facts komt, morgen werkt.
3. **Zelf toevoegen.** Foto van de verpakking en van het etiket, Vision leest het etiket (op het toestel), de gebruiker controleert de waarden. Opslaan via `submit-product`: die controleert de waarden (§5.1), maakt de gedeelde rij (`source = 'user'`, `is_verified = false`) en bewaart de inzending in `product_submissions`. Terugsturen naar Open Food Facts is een latere, aparte keuze van de gebruiker (RISKS R-02).
4. **Offline en onbekend.** De app zegt dat het product nog niet bekend is en biedt aan het nu als eigen product in te voeren (privé) of de scan te bewaren voor later.

Onverpakte producten (groente, vlees, brood) komen uit NEVO als gedeelde rijen met `source = 'nevo'`, zonder barcode, één keer geïmporteerd door een script (fase 2).

### 5.1 Normaliseren

Alle waarden staan **per 100 g of per 100 ml** (`quantity_unit`). Uit Open Food Facts:

| Veld | Bron | Regel |
|---|---|---|
| `name` | `product_name_nl`, `_en`, `_de`, anders `product_name` onder de taal `lc` | lege namen overslaan; geen enkele naam → niet opslaan |
| `kcal_100` | `nutriments["energy-kcal_100g"]`, anders `energy_100g` (kJ) ÷ 4,184 | afronden op 0,1 |
| `protein_100` … `salt_100` | `proteins_100g`, `carbohydrates_100g`, `sugars_100g`, `fat_100g`, `saturated-fat_100g`, `fiber_100g`, `salt_100g` | ontbreekt → `null`, nooit 0 |
| `quantity_unit` | `ml` als `product_quantity_unit` of `serving_size` op ml/l/cl eindigt, anders `g` | – |
| `serving_size` | `serving_quantity` | alleen als > 0 |
| `image_url` | `image_front_url` | – |

De veldnamen van Open Food Facts komen uit hun API-documentatie; controleer ze bij het bouwen met één echte aanroep en leg het antwoord vast als testbestand.

Controles vóór opslaan (in de Edge Function, met dezelfde grenzen als de `check`-regels):

- Een waarde buiten zijn grens (bijvoorbeeld eiwit > 100 per 100 g) wordt `null`.
- Zijn kcal en alle drie de macro's bekend en wijkt `4·eiwit + 4·koolhydraten + 9·vet` meer dan 25 % én meer dan 30 kcal af van `kcal_100`, dan klopt het etiket niet: het product krijgt `is_verified = false` en de app toont "Controleer de waarden".

Omrekenen bij het loggen (`FoodMath` in FitlingCore, afgerond op één decimaal zoals de database het bewaart):

- hoeveelheid in g of ml: `waarde = per100 × hoeveelheid / 100`;
- hoeveelheid in porties: eerst `hoeveelheid × serving_size`, dan dezelfde formule. Zonder `serving_size` kan niet in porties worden gelogd.

### 5.2 Onvolledige data

| Wat ontbreekt | Wat de app doet |
|---|---|
| kcal | Het product kan niet gelogd worden. De app vraagt de kcal per 100 g en bewaart het resultaat als eigen product van de gebruiker; de gedeelde rij blijft ongewijzigd. |
| één of meer macro's | Loggen kan. De ontbrekende waarde wordt als onbekend opgeslagen (`null`), telt als 0 en het dagoverzicht meldt "van 2 producten is het eiwit onbekend". |
| portiegrootte | Alleen loggen in gram of milliliter. |
| naam in de taal van de gebruiker | `LocalizedText.text(preferring:)`: eerst de talen van de gebruiker, dan Engels, dan Nederlands, dan wat er is. |

## 6. Aanbiedingen

De app haalt zelf nooit aanbiedingen op bij winkels. Een dagelijkse backend-job doet dat.

```ts
// supabase/functions/sync-offers/provider.ts
export interface OfferProvider {
  /** Gelijk aan supermarkets.id. */
  readonly supermarketId: string;
  /** Alle aanbiedingen die nu of binnenkort gelden. */
  fetchOffers(): Promise<RawOffer[]>;
}

export interface RawOffer {
  externalId: string;
  title: string;
  brand?: string;
  gtin?: string;
  quantityValue?: number;
  quantityUnit?: "g" | "ml" | "piece";
  priceCents: number;
  regularPriceCents?: number;
  promoLabel?: string;
  validFrom: string; // "2026-11-18"
  validTo: string;
  imageUrl?: string;
}
```

- `sync-offers` loopt alle aangemelde providers langs, normaliseert (barcode via dezelfde regel als de app, `search_title` in kleine letters zonder accenten) en schrijft met `upsert` op `(supermarket_id, external_id, valid_from)`. Een provider die faalt, houdt de andere niet tegen. Aanbiedingen die een week verlopen zijn, worden verwijderd.
- Een bron toevoegen of vervangen is één bestand dat `OfferProvider` implementeert. Welke bronnen gebruikt mogen worden, is een juridische vraag die vóór fase 6 beantwoord moet zijn (RISKS R-13). Tot die tijd bestaat er alleen een provider met testdata.
- Plannen: dagelijks via Supabase Cron. De precieze opzet (pg_cron met een HTTP-aanroep of een geplande functie) staat in de Supabase-documentatie en wordt bij fase 6 gekozen; het raakt de rest van het ontwerp niet.

### 6.1 Matchen gebeurt op het toestel (D-09)

De app haalt de geldige aanbiedingen van de favoriete supermarkten op (`offers` waar `valid_to >= vandaag`) en matcht ze lokaal met de lijst. Dat werkt offline, en de server hoeft niet door ieders boodschappenlijst te lopen.

Per lijst-item, in deze volgorde:

1. **Barcode.** Het item heeft een product met `gtin` en een aanbieding heeft dezelfde `gtin` → zekere match.
2. **Naam en hoeveelheid.** Anders:
   - Beide namen terugbrengen tot hun woorden: kleine letters, accenten weg, leestekens weg, hoeveelheden en eenheden ("500 g", "1,5 l", "6 stuks", "6x330") eruit, stopwoorden weg (`de het een van met en voor`) en woorden die niets over het product zeggen, zoals de naam van de winkel.
   - Noemt de aanbieding een ander merk dan het product: geen match.
   - Hebben beide een hoeveelheid in dezelfde eenheid en is de ene meer dan vier keer de andere: geen match (500 g gehakt is geen 2,5 kg gehakt). Ontbreekt een hoeveelheid, dan telt dit niet mee.
   - Score = per woord van het lijst-item 1 als het in de aanbieding staat, 0,75 als er een verwant woord staat, anders 0; gedeeld door het aantal woorden. Verwant: beide woorden zijn minstens vier letters, beginnen hetzelfde en verschillen hoogstens in de laatste twee letters van het kortste woord ("tomaat" en "tomaten"). Hetzelfde merk: +0,2.
3. **Uitkomst.** Zeker: dezelfde barcode, of precies dezelfde woorden. Onzeker: score ≥ 0,6. Lager: geen match. "Melk" tegenover "Halfvolle melk" is dus onzeker, want "Chocolade melk" zou net zo goed passen: de gebruiker beslist.

Wat de app laat zien:

- **Zeker:** de prijs en de winkel staan bij het item, en het item telt mee in "totaal per winkel".
- **Onzeker:** onder het item staat "Mogelijk in de aanbieding: *titel van de aanbieding*" met de winkel en de prijs. Het telt **niet** mee in de totalen tot de gebruiker één keer tikt op "Klopt". Dat antwoord wordt lokaal onthouden voor die naam.
- De goedkoopste winkel per item en het totaal per winkel rekenen alleen met zekere en bevestigde matches. Staat een item bij een winkel niet in de aanbieding, dan toont het totaal van die winkel "+ 3 items zonder prijs": de app verzint geen gewone prijs.

Dit staat als pure functie in `OfferMatcher` (FitlingCore), met `cheapestPerItem` en `storeTotals` voor de totalen. Het is bewust een eenvoudige woordvergelijking: uitlegbaar ("deze woorden kwamen overeen") en goed te testen. Blijkt hij in de praktijk te vaak mis, dan is dat een taak voor Fable (TASKS 6.6).

## 7. De engines

De code is de bron; dit zijn de regels in het kort. Elke constante staat met naam in de engine.

### NutritionEngine

- BMR volgens Mifflin-St Jeor; voor "anders" het gemiddelde van de constanten voor man en vrouw.
- TDEE = BMR × activiteitsfactor (1,2 · 1,375 · 1,55 · 1,725 · 1,9).
- Doel = TDEE × doelfactor (afvallen 0,80 · spieropbouw 1,10 · onderhoud 1,00 · recomp 0,95), afgerond op 10.
- **Ondergrens:** een voorstel komt nooit onder BMR × 1,1 (naar boven afgerond op 10). `floorApplied` zegt of de ondergrens is gebruikt, zodat de app dat kan uitleggen.
- Eiwit = gewicht × 1,6–2,2 g/kg per doel; vet = 25 % van de kcal; koolhydraten = de rest, nooit negatief.
- Waarschuwingen (`TargetWarning`), ook voor een doel dat de gebruiker zelf intypt: onder de ondergrens, onder 1500/1200 kcal, meer dan 25 % onder het verbruik. De app waarschuwt en blokkeert niet (D-10).
- HealthKit: met de schakelaar aan telt de helft van de trainingsenergie van die dag bij het dagbudget op, als koolhydraten (D-11).

### CreatureEngine

- **Toestand** uit de zeven dagen vóór vandaag. Alleen dagen die voor minstens de helft van het doel zijn gelogd tellen mee; een dag met alleen een ontbijt zegt niets over te weinig eten. Minder dan drie zulke dagen: normaal.
  - fit: 90–110 % van het doel · te veel: boven 110 % · te weinig: onder 75 % · normaal: daartussen.
  - slaapt: drie dagen achter elkaar niets gelogd. Eén gelogde maaltijd maakt het wakker. Het wezentje gaat nooit dood.
- **Vorm** is een getal van 0 (slank en fit) tot 1 (rond), start 0,3, hoogstens 0,05 per dag.
  - fit: richting 0 · te veel: richting 0,5–1,0, naar gelang hoe ver boven het doel (150 % = helemaal rond).
  - **te weinig, normaal en slapen veranderen de vorm niet.** Slanker worden is nooit het gevolg van te weinig eten.
- **XP** per afgeronde dag: 10 voor loggen, 40 binnen ±10 % van het doel, 20 voor het eiwitdoel, 30 voor een training. XP gaat nooit omlaag.
- **Herstel:** na zeven of meer dagen te veel of te weinig terug naar fit: eenmalig 150 XP.
- **Level** L vraagt 50 × L × (L − 1) XP (level 2 bij 100, level 5 bij 1000). Groeistadia bij level 1, 3, 6, 10, 15. Accessoires bij level 2, 4, 6, 8, 11, 15; een extra kleur bij level 5 en 12.
- **Stemming en energie** volgen uit de toestand; een dag zonder log geeft "honger" vóór het slapen komt.
- `advance` verwerkt alle afgeronde dagen sinds de laatste keer en is veilig om vaker aan te roepen. `snapshot` geeft wat de UI nodig heeft.
- **Meldingen:** sleutels `creature.message.<onderwerp>.<toon>.<1–3>`, met onderwerp `fit`, `normal`, `tooMuch`, `tooLittle`, `asleep`, `hungry` en toon `sweet`, `funny`, `coach`. De engine kiest per dag een andere variant. De teksten zelf worden in fase 3 geschreven. Voorbeeld per toon voor `hungry` (van de gebruiker): lief "Ik heb honger 🥺", grappig "Mijn maag knort harder dan jouw wekker", coach "Tijd voor eiwit. Wat eet je?".

De getallen van het wezentje (drempels, XP, levels) zijn een eerste afstelling. Bijstellen na echt gebruik is een taak voor Fable (TASKS 3.9).

### ProgressionEngine

- Alle sets op het werkgewicht halen de bovenkant van de range met RPE ≤ 8 (een set zonder RPE telt als makkelijk genoeg) → zwaarder: het kleinste aantal hele stappen dat minstens 2,5 kg (compound) of 1 kg (isolatie) toevoegt.
- Is die stap meer dan 10 % van het gewicht (dumbbells per 2 kg, een machine per 5 kg), dan eerst twee herhalingen boven de range op elke set.
- Twee trainingen achter elkaar (minder dan 14 dagen ertussen) waarbij meer dan de helft van de sets onder de onderkant blijft → 10 % terug, naar beneden afgerond op een stap.
- 14 dagen of meer niet gedaan → 10 % terug; 28 dagen of meer → 20 % terug.
- Lichaamsgewicht zonder extra gewicht: "maak het zwaarder" of "maak het makkelijker" in plaats van kilo's.
- Geschatte 1RM volgens Epley, alleen voor 1–12 herhalingen. PR's: zwaarste gewicht, hoogste 1RM, meeste herhalingen op een gewicht. De eerste training zet de basis en geeft geen PR's.
- Volume per spiergroep per week (maandag–zondag): een set telt heel voor een primaire en half voor een secundaire spier.

### WeekMenuPlanner

Aanpak: **gretig kiezen per maaltijd, daarna per dag corrigeren.**

1. Recepten filteren op uitsluitingen (ingrediënt of tag), kooktijd en maaltijdsoort.
2. Per dag, grootste maaltijd eerst: het recept met de beste score. De score telt hoe goed de kcal bij dat deel van de dag passen (porties in stappen van een kwart, tussen een half en twee), hoeveel eiwit er tekortkomt, de prijs als er een budget is, en of het recept deze week al gebruikt is. Een recept komt hoogstens op twee dagen voor.
3. Meal-prep: het avondeten van gisteren schuift door als restje, als het recept zich daarvoor leent. Samen is dat "één keer koken, twee dagen eten".
4. Correctie per dag: porties een kwart omhoog of omlaag tot de dag binnen ±5 % van het kcal-doel valt. Is er daarna te weinig eiwit, dan eerst een grotere portie van het eiwitrijkste gerecht, dan een gerecht wisselen voor een eiwitrijker.
5. Budget: zolang het totaal boven het budget ligt, de wissel doen die het meest bespaart, mits de dag zijn kcal en eiwit houdt.
6. Wat niet lukt, komt terug als `MenuIssue` (geen recepten voor een maaltijd, dag buiten de marge, eiwit tekort, boven budget). De app toont dat eerlijk in plaats van een menu dat niet klopt.

Waarom geen exacte optimalisatie: het probleem is klein (zeven dagen, drie of vier maaltijden), de marge van 5 % en de portiestappen geven speling, en het moet op het toestel direct, voorspelbaar en zonder extra library werken. Dezelfde invoer met hetzelfde `seed` geeft hetzelfde menu; "nieuw menu" is een ander seed. Vastgezette maaltijden blijven precies staan.

## 8. Beslissingen

| Nr | Beslissing | Alternatieven | Reden |
|---|---|---|---|
| D-01 | Rekenregels in een los pakket zonder Apple-frameworks | In de app-target | Tests draaien gratis op Linux; er is geen Mac en de Mac-minuten zijn beperkt |
| D-02 | Fase 1 wordt opnieuw gebouwd op dit fundament; de eerdere code is naslag op branch `fase-1` | Voortbouwen op de bestaande code | Keuze van de gebruiker (2026-11-18). Overnemen wat al getest is, mag en is zuiniger dan opnieuw schrijven |
| D-03 | Wachtwoord vergeten geeft altijd dezelfde melding | De check "e-mail niet bekend" uit PROMPT.md | Keuze van de gebruiker. Niemand kan zo opvragen wie een account heeft bij een gezondheidsapp |
| D-04 | Laatste wijziging wint, per rij, op `updated_at`; de server corrigeert klokken die voorlopen | Samenvoegen per veld; CRDT's | Eén gebruiker, meestal één toestel, kleine rijen. Eenvoudig te begrijpen en te testen |
| D-05 | Verwijderen met `deleted_at`, opruimen na 90 dagen | Direct verwijderen | Een verwijdering moet een ander toestel kunnen bereiken |
| D-06 | Geen unieke eis op rijen die een toestel offline aanmaakt, behalve de sleutel | Uniek per gebruiker en dag of product | Twee toestellen offline zouden anders een rij maken die de server voor altijd weigert |
| D-07 | `supabase/schema.sql` is de enige bron tot er een productiedatabase is; daarna wordt het de eerste migratie en gaat elke wijziging via een migratie | Nu al losse migraties per fase | Er is nog niets uitgerold. Eén bestand is te overzien en CI test precies wat er staat |
| D-08 | Dagen als `Day` en als tekst `"2026-11-18"` | `Date` op middernacht UTC | Een `Date` verschuift met de tijdzone. De eerdere fase 1 had daar een aparte kalender en een open testgat voor |
| D-09 | Aanbiedingen matchen op het toestel | Matchen in de backend-job (PROMPT.md) | Werkt offline en de server leest geen boodschappenlijsten. De job haalt alleen aanbiedingen op |
| D-10 | Een handmatig doel onder de ondergrens geeft een waarschuwing, geen blokkade | Blokkeren | De ondergrens geldt voor wat de app voorstelt. Wie met een diëtist een ander doel heeft, moet dat kunnen invullen |
| D-11 | De helft van de trainingsenergie telt bij het budget op | Alles; niets | De activiteitsfactor dekt al een deel van de training en horloges schatten hoog |
| D-12 | Te weinig eten verandert de vorm van het wezentje niet en geeft geen XP | Slanker worden bij minder eten | "Minder eten wordt nooit beloond" (PROMPT.md). De slanke vorm is alleen te bereiken door op het doel te eten |
| D-13 | Dagen die voor minder dan de helft van het doel zijn gelogd, tellen niet mee in het gemiddelde | Elke gelogde dag telt | Half loggen zou anders als te weinig eten gelden en het wezentje onterecht moe maken |
| D-14 | Inhoud uit de database is `jsonb` per taal; interfaceteksten staan in de String Catalog | Alles in de String Catalog | Producten, recepten en oefeningen veranderen zonder app-update en Open Food Facts levert namen in veel talen |
| D-15 | Eén tabel `products` voor de gedeelde cache en eigen producten | Twee tabellen | Een voedingslog verwijst zo altijd naar één soort product |
| D-16 | De gedeelde cache wordt alleen door Edge Functions geschreven | Clients schrijven zelf | Eén schrijver voorkomt dubbele en gemanipuleerde producten en houdt sleutels van bronnen op de server |
| D-17 | Lid worden van een lijst alleen via een code; leden zien alleen elkaars opgegeven naam | Uitnodigen op e-mailadres | Geen manier om te testen of een e-mailadres een account heeft; profielen blijven privé |
| D-18 | Realtime is een seintje om te pullen, geen tweede manier om data toe te passen | De inhoud van de melding toepassen | Eén pad voor binnenkomende data, dus één plek voor de conflictregel |
| D-19 | Trainingen uit HealthKit en voortgangsfoto's blijven op het toestel | Meesturen naar de server | Privacy, en de regels van Apple voor gezondheidsdata (RISKS R-05) |
| D-20 | Weekmenu: gretig kiezen met correctie | Geheeltallige optimalisatie | Zie §7 |

## 9. Bewust nog open

- Welke bronnen voor aanbiedingen gebruikt mogen worden (RISKS R-13).
- Of er een betaalde productbron komt en welke (RISKS R-04).
- De definitieve teksten van de meldingen van het wezentje en de afstelling van zijn getallen (TASKS 3.6 en 3.9).
- De animatietechniek van het wezentje (SpriteKit of Rive): de engine is er onafhankelijk van; de keuze valt in fase 3.
- De vormgeving: de richting "Verzamelfiguren" is gekozen; het werk staat lokaal op branch `herontwerp-verzamelfiguren` (TASKS 1.2).

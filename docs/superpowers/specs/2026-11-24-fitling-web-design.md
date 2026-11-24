# Fitling op het web: ontwerp

Status: goedgekeurd (2026-11-24). De gebruiker koos aanpak A en liet de open keuzes aan Claude ("kies het beste pad"). Die keuzes staan onder "Beslist na het nalezen".

## Waarom

Fitling staat nog niet in de App Store: het Apple Developer Program ontbreekt (UNFORGET S1). Tot die er is, moeten mensen Fitling toch kunnen gebruiken: in de browser, en op een iPhone via "Zet op beginscherm" als icoon met een eigen venster. De iOS-app blijft bestaan en blijft de hoofdversie. Later gebruiken mensen dezelfde gegevens in beide, want ze werken op dezelfde Supabase.

## Doelen

- **Alles van de iOS-app, 1 op 1:** wat de iOS-app nu kan, kan de webversie ook, met hetzelfde uiterlijk. Uitzonderingen staan hieronder onder "Wat op het web niet kan".
  - Schermen: welkom en inloggen, onboarding, dagdoel en profiel, account en "Over Fitling", vandaag, loggen (zoeken, scannen, portie, eigen product, water), partner (kiezen, aanpassen, groeien, accessoires), training (schema's, samenstellen, loggen, rusttimer, coach, voortgang, lichaam, voortgangsfoto's, oefeningen met animatie), menu (weekmenu, recepten, voorkeuren), boodschappen (lijst, delen, aanbiedingen, supermarkten) en het exporteren van je gegevens.
- **Dezelfde getallen:** kcal, macro's, trainingsadvies, de generator, groei van de partner, weekmenu en aanbiedingen komen uit dezelfde code als op iOS (FitlingCore). Een verschil in iemands dagdoel tussen iPhone en web mag niet kunnen.
- **Eén bron voor teksten en beelden:** teksten (nl, en, de), kleuren, partnerlagen, oefenanimaties en receptfoto's komen uit de bestanden van de iOS-app.
- **Op het beginscherm van een iPhone voelt het als een app:** eigen icoon en naam, geen adresbalk, de veilige randen van het scherm gerespecteerd, de tabbalk onderaan.
- **Gratis:** hosting en gereedschap kosten niets.

## Niet-doelen

- De iOS-app vervangen of herschrijven. SwiftUI blijft.
- Een Android-app.
- Een eigen ontwerp voor grote schermen. Op een laptop staat de app in een kolom ter breedte van een telefoon.

## Anti-doelen (dan is het mislukt, ook al werkt het)

- Getallen die op web anders uitkomen dan op iOS.
- Een generieke web-look (standaard-knoppen, een andere letter, een hamburgermenu) in plaats van de Verzamelfiguren-wereld uit DESIGN.md.
- Geheime sleutels in de webcode. Alleen de publishable key van Supabase mag erin, net als in de app.
- Gegevens die op iOS en web niet samengaan, bijvoorbeeld een rij die de iPhone-sync niet meer kan lezen.

## Wat op het web niet kan, en wat er gebeurt

| Onderdeel | Op het web |
|---|---|
| Inloggen met Apple | Niet zonder het developer account. De knop ontbreekt; inloggen met e-mail werkt. |
| Inloggen met Google | Pas als Google in Supabase is ingesteld (S13); tot dan geen knop. |
| HealthKit (stappen, trainingen uit Gezondheid) | Browsers kunnen er niet bij. Dit onderdeel ontbreekt, zonder melding of lege plek. |
| Widget, Live Activity | Bestaan op iOS ook nog niet (S18). |
| Trainingsenergie uit Gezondheid | Telt op iOS mee in het dagdoel als `counts_workout_energy` aan staat, en geldt daar als trainingsdag voor de partner. Op het web zit dit niet: de instelling is verborgen, en het dagdoel staat er zonder die energie. |
| Offline loggen | De eerste versie werkt alleen online. Loggen zonder verbinding komt als laatste fase (zie Fases). |
| Voortgangsfoto's | Blijven in de browser (IndexedDB), net als op iOS alleen op het toestel. Wie de browsergegevens wist, raakt ze kwijt; dat staat bij het scherm. |
| Herinneringen van de partner | Op het beginscherm van een iPhone (iOS 16.4+) via Web Push. Daar is iets op de server voor nodig (zie Fase 7). |

## Aanpak

Bekeken:

- **A. Webapp in TypeScript, met FitlingCore als WebAssembly (gekozen door de gebruiker).** De schermen worden opnieuw gebouwd voor het web. De rekenregels worden uit dezelfde Swift-code gecompileerd naar WebAssembly, dus één bron en dezelfde 224 tests. Nadeel: elk nieuw scherm moet daarna twee keer gebouwd worden.
- **B. Alles in TypeScript.** Eenvoudiger gereedschap, maar de rekenregels bestaan dan twee keer en kunnen uit elkaar lopen. Dat is het eerste anti-doel.
- **C. iOS en web samen opnieuw in Flutter of React Native.** Eén codebase, maar de SwiftUI-app en zijn uiterlijk gaan weg. Dat is in strijd met "de iOS-versie houden".

**Terugvaloptie als WebAssembly niet lukt** (zie Fase 0): FitlingCore wordt met de hand naar TypeScript vertaald. Een Swift-test schrijft voor elke rekenregel invoer en uitkomst naar JSON-bestanden. De TypeScript-tests rekenen die na, zodat beide versies aantoonbaar hetzelfde uitkomen. Dit valt onder A en vraagt geen nieuwe keuze van de gebruiker.

## Hoe

### Waar het staat

- In dezelfde repository, in de map `web/`. De iOS-app, FitlingCore, `supabase/` en de ontwerpbestanden blijven waar ze zijn.
- In CI komt een job "Web" bij. Die bouwt de rekenregels naar WebAssembly, maakt de webapp, en draait de unit- en browsertests met schermafbeeldingen. De andere jobs blijven zoals ze zijn.

### Gereedschap (keuzes van de bouwer, hier vastgelegd)

- **Taal en bouw:** TypeScript, React en Vite. Een statische site, zonder eigen server.
- **Gegevens:** `@supabase/supabase-js` met de publishable key, op dezelfde tabellen. Toegang per gebruiker regelt de beveiliging per rij die er al is.
- **Rekenregels:** FitlingCore met de officiële Swift SDK voor WebAssembly (Swift 6.x), via een dunne Swift-laag. Elke functie krijgt JSON en geeft JSON terug. De webapp roept die laag aan via JavaScriptKit; meer dan één functie per regel komt er niet.
  - Tijdzone: `Day(_:timeZone:)` is het enige gebruik van `TimeZone`. De weblaag geeft de afwijking van de browser in seconden mee, zodat WebAssembly geen tijdzonegegevens nodig heeft.
- **Barcode scannen:** camera via `getUserMedia`, herkenning met `@zxing/browser` (open source). Safari heeft geen ingebouwde barcodeherkenning. Opzoeken gaat via de bestaande Edge Function `lookup-product`.
- **Lettertype:** de systeemletter (`system-ui`, `ui-rounded` voor de ronde variant). Op Apple-toestellen is dat SF Pro en SF Rounded, dus hetzelfde als in de app. De licentie van SF staat niet toe dat we de letter zelf meesturen, en dat gebeurt dus ook niet. Op andere toestellen valt het terug op de systeemletter daar.
- **Hosting:** GitHub Pages vanuit de publieke repository, gebouwd en gepubliceerd door GitHub Actions. Dat is gratis en vraagt geen nieuw account. Het adres wordt `https://solidhawk.github.io/fitling/`.

### Eén bron

Bij het bouwen genereert een script uit de iOS-bestanden:

- **Teksten:** `Localizable.xcstrings` wordt JSON per taal. Meervoud gaat via `Intl.PluralRules`, net als de catalogus. Ontbreekt een tekst, dan faalt de bouw.
- **Kleuren:** de colorsets worden CSS-variabelen, voor licht en donker (`prefers-color-scheme`).
- **Beelden:** partnerlagen (1344 lagen), oefenvellen (WebP) en receptfoto's worden gekopieerd, met dezelfde namen.

### Rekenregels die nu in de app zitten

- **Wat:** een deel van wat de getallen bepaalt staat nu in de app, niet in FitlingCore. Bijvoorbeeld:
  - welk dagdoel op een dag geldt (`targets(on:for:)`);
  - de dagen die de partner beoordeelt (`CreatureHistory`);
  - de coach en de kandidaten van de generator (`TrainingStore`);
  - de invoer van het weekmenu (`MenuStore`).
- **Waarheen:** die logica verhuist naar FitlingCore, per fase, vóór het scherm op het web komt. De app roept daarna FitlingCore aan, met dezelfde uitkomst.
- **Controle:** per verhuizing bewijzen de bestaande app-tests dat er niets verandert. Nieuwe rekentests komen in FitlingCoreTests.
- **Akkoord:** de gebruiker gaf dat voor deze refactor op 2026-11-24.

### Gegevens en sync

- **Schrijven en lezen:** de webapp schrijft direct naar Supabase en houdt zich aan de afspraken van de sync.
  - `updated_at` is de klok van de client; de laatste wijziging wint.
  - Verwijderen is `deleted_at` zetten, nooit echt wissen.
  - `synced_at` zet de server.
  - Ids zijn UUID's van de client.
  - Lezen filtert op `deleted_at is null`.
- **Samen met de iPhone:** zo leest de iPhone-sync wat op het web gemaakt is, en andersom.
- **Afgeleide ids:** waar de iOS-app een id afleidt (D-23: id's van samengestelde trainingen), komt dat uit FitlingCore, dus op beide hetzelfde.
- **Geen migratie:** de database verandert niet, behalve in Fase 7 (Web Push).
- **Welk project:**
  - Fase 0 tot en met 2 draaien op `fitling-dev`, voor de gebruiker en testers die weten dat hun gegevens bij een databasewijziging kunnen verdwijnen (`reset-dev.sql`).
  - Een apart productieproject (UNFORGET S4) komt er vóór de webversie breder gedeeld wordt. Daarbij horen ook een eigen mailserver (S2) en de secrets in GitHub (S10).
- **Edge Functions in de browser:** `lookup-product` en `delete-account` sturen nu geen CORS-headers en beantwoorden het voorverzoek van de browser niet. Dat komt erbij, met tests. Ze op het echte project zetten gebeurt door of met akkoord van de gebruiker.

### Inloggen

- **Hoe:** e-mail en wachtwoord, wachtwoord vergeten en de bevestigingsmail, zoals op iOS.
- **Wat Supabase moet weten:** de links in de mails moeten naar het webadres kunnen wijzen. Daarvoor moet het webadres in Supabase bij `additional_redirect_urls` komen te staan. Dat is een wijziging aan het echte project en gebeurt pas na akkoord van de gebruiker.

### Uiterlijk

- **Wereld:** dezelfde als de app, volgens DESIGN.md: lila grond (donker: diep pruim), witte kaarten, linten per partner, naamplaatjes, de 3D-partner als gestapelde lagen met kleurverschuiving.
- **Navigatie:** een tabbalk onderaan met dezelfde vijf tabbladen. Op elk tabblad stapelen de schermen zoals op iOS, met een terugknop en terugvegen. Bladen ("sheets") komen van onder.
- **Iconen:** SF Symbols mogen buiten Apple-software niet gebruikt worden. Op het web komen daarom iconen uit een vrije set (Lucide, ISC-licentie) die er het dichtst bij liggen. Dit is het enige zichtbare verschil met de app.
- **Toegankelijkheid:** een label voor elk bedieningselement, tikvlakken van minstens 44 pt, contrast AA, tekst die meegroeit met de lettergrootte van de browser, en "Verminder beweging" via `prefers-reduced-motion`. In CI controleert `axe-core` dit in de browsertests, zoals Apples audit dat in de iOS-tests doet.

### Fases

Elke fase eindigt met groene CI, schermafbeeldingen voor de gebruiker en een PR. De volgorde volgt de app.

0. **Fundament:**
   - FitlingCore als WebAssembly, als proef met één rekenregel (dagdoel). Lukt dat niet binnen deze fase, dan geldt de terugvaloptie.
   - Het generatiescript voor teksten, kleuren en beelden.
   - Een lege app met de tabbalk, live op GitHub Pages.
   - De job "Web" in CI.
1. Welkom, inloggen met e-mail, onboarding, partner kiezen, dagdoel en profiel, account (met exporteren en account verwijderen), "Over Fitling".
2. Vandaag, loggen (zoeken, recent en favoriet, portie, eigen product), scannen, water.
3. Partner: tabblad, groei, stemming, accessoires, kleuren, niveau en XP.
4. Training: schema's, samenstellen, training loggen met rusttimer, coach, voortgang en grafieken, lichaam, voortgangsfoto's, oefeningen met animatie.
5. Menu: weekmenu maken en aanpassen, recepten (ook eigen), voorkeuren, loggen met één tik.
6. Boodschappen: lijst, delen met een code, aanbiedingen, supermarkten.
7. Beginscherm en afronden:
   - manifest en icoon;
   - herinneringen via Web Push. Daarvoor zijn een tabel voor de abonnementen en een Edge Function nodig, dus wel een migratie, met akkoord;
   - loggen zonder verbinding (wachtrij in IndexedDB);
   - een laatste ronde vormgeving met `impeccable`.

### Testen

- **Rekenregels:** de bestaande Swift-tests (224). Daarbij een paar tests die de WebAssembly-laag aanroepen en dezelfde uitkomst verwachten.
- **Webapp:** unit-tests met Vitest. Browsertests met Playwright (Safari-engine WebKit en Chromium, telefoonformaat) per fase, met schermafbeeldingen als artefact, zoals de UI-tests van iOS.
- **Gegevens:** de browsertests draaien tegen een lokale Supabase in CI (de job "Supabase" doet dat al), nooit tegen het echte project.

## Beslist na het nalezen

Een bouwer die niets kon vragen las het ontwerp en stelde vijf vragen. Wat ermee gebeurde:

1. **Welk Supabase-project:** `fitling-dev` voor Fase 0–2, productie vóór breder delen. Keuze van Claude, in opdracht van de gebruiker.
2. **Logica naar FitlingCore of herschrijven:** naar FitlingCore. Keuze van Claude, in opdracht van de gebruiker.
3. **Trainingsenergie uit Gezondheid:** op het web verborgen, en het dagdoel zonder die energie.
   - Gebruikt iemand later beide, dan rekent de iPhone die energie wel mee. Het dagdoel kan dan per toestel verschillen, en de partner volgt de laatste schrijver.
   - Dit is een eigen keuze van Claude. Opnieuw bekijken als iemand iPhone en web tegelijk gebruikt.
4. **CORS in de Edge Functions:** komt erbij (zie "Gegevens en sync").
5. **Web Push:** de vorm wordt beslist bij Fase 7.

## Wat open ligt voor de gebruiker

- **App-icoon:** er is er nog geen. Voor het beginscherm is er een nodig (Fase 7; voor iOS later ook).
- **Akkoord op het echte Supabase-project:**
  - het webadres bij de toegestane links (Fase 1);
  - de Edge Functions met CORS op het project zetten (Fase 1–2);
  - de migratie voor Web Push (Fase 7).
- **De publishable key en het adres van `fitling-dev` voor de webbouw (Fase 1):** als GitHub-variabele, door de gebruiker gezet (S10).
- **Vóór breder delen:** het productieproject, een mailaccount (bijvoorbeeld Brevo, gratis) en de secrets.

## Wat aan de bouwer is

- De mappen binnen `web/`, de componenten en de state-aanpak.
- Hoe de dunne Swift-laag de functies van FitlingCore doorgeeft, binnen "JSON erin, JSON eruit".
- Welk Lucide-icoon het dichtst bij elk SF Symbol ligt.

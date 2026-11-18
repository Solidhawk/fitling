Je bent een senior iOS-engineer. Bouw met mij een native iOS-app voor sport & voeding, werktitel "Fitling". Werk in fases, begin met een plan, mappenstructuur en datamodel, en vraag om akkoord voordat je fase 1 bouwt. Schrijf schone, geteste Swift-code.

## Tech stack (verplicht)
- Swift 6, SwiftUI, minimaal iOS 17, MVVM + Observation (@Observable)
- Lokale opslag: SwiftData (offline-first), sync naar backend
- Backend: Supabase (Postgres, Auth, Storage, Edge Functions)
- Barcodescanner: VisionKit DataScannerViewController (EAN-13, EAN-8, UPC-A)
- Lokalisatie: String Catalogs (.xcstrings), géén hardcoded teksten
- HealthKit: workouts, stappen en actieve energie lezen (Garmin/Apple Watch syncen via Apple Health)
- Swift Package Manager voor dependencies, zo min mogelijk externe libraries

## Functies

### 1. Registratie & login
- Inloggen met Sign in with Apple, Google en e-mail/wachtwoord (Supabase Auth)
- E-mailverificatie bij registratie
- Wachtwoord vergeten: als het e-mailadres niet bestaat, toon de melding "Er is geen account met dit e-mailadres" en bied direct "Account aanmaken" aan. Als het wel bestaat: stuur een reset-link. Implementeer de check via een Edge Function met rate limiting (max 5 pogingen per uur per IP/apparaat).
- Account verwijderen in de app (verplicht volgens App Store-regels)
- Onboarding: lengte, gewicht, leeftijd, geslacht, activiteitsniveau, doel (afvallen / spieropbouw / onderhoud / recomp) → bereken BMR (Mifflin-St Jeor), TDEE, kcal-doel en macro's (eiwit 1,6–2,2 g/kg). Gebruiker kan alles handmatig aanpassen.

### 2. Wezentje (tamagotchi)
- Gebruiker kiest en benoemt een wezentje bij onboarding
- Statussen: energie, humeur, conditie, en een lichaamsvorm (slank ↔ normaal ↔ dik), geanimeerd (SpriteKit of Rive)
- Dagelijkse logica:
  - Eten gelogd binnen ±10% van kcal-doel → wezen blij, groeit/levelt
  - Structureel > 10% boven doel (rollend 7-daags gemiddelde) → wezen wordt geleidelijk dikker en trager
  - Structureel ver onder doel (> 25% eronder) → wezen wordt moe/zwak (géén beloning voor te weinig eten)
  - Niets gelogd → wezen wordt verdrietig/hongerig; na 3 dagen "slaapt" het (nooit permanent dood)
  - Eiwitdoel gehaald en training voltooid → bonus XP, accessoires/outfits vrijspelen
- Vriendelijke, niet-beschamende teksten. Herstel moet altijd mogelijk zijn.
- Widget (WidgetKit) en Live Activity met het wezentje op het beginscherm
- Pushmeldingen vanuit het wezentje ("Ik heb honger, wat heb je als lunch gegeten?"), instelbaar

### 3. Voeding loggen
- Barcode scannen → zoek product op in deze volgorde:
  1. Eigen cache/database (Supabase)
  2. Open Food Facts API v2/v3 (gratis, geen key; zet User-Agent "Fitling/1.0 (contact-email)"; vang 503's op met retry + backoff)
  3. Optioneel commerciële fallback via backend: FatSecret Platform API of Nutritionix (key alleen server-side)
  4. Niet gevonden → gebruiker voegt product toe (foto van verpakking + voedingswaarde-label via Vision OCR), optioneel terugsturen naar Open Food Facts
- Zoeken op naam, recent/favoriet, maaltijden (ontbijt/lunch/diner/snack), porties en grammen
- Onverpakte producten (groente, vlees, brood): NEVO-tabel (RIVM) importeren als basisdataset
- Dagoverzicht: kcal-ring, eiwit/koolhydraten/vet, water
- Foto's: elk product en gerecht heeft een afbeelding (Open Food Facts-foto, eigen foto, of receptfoto). Afbeeldingen cachen; placeholder-illustratie als er geen foto is.

### 4. Recepten & weekmenu
- Receptendatabase met foto, ingrediënten, bereiding, kcal en macro's per portie
- Weekmenu-generator: op basis van kcal-/macrodoel, voorkeuren, uitsluitingen (bijv. ingrediënten die je niet lust), budget en kooktijd
- Gebruiker kan gerechten verslepen, wisselen of vastzetten; maaltijd uit het menu met één tik loggen
- Restjes en meal-prep (2× koken, 2 dagen eten)

### 5. Boodschappenlijst & aanbiedingen
- Weekmenu → automatisch samengevoegde boodschappenlijst (hoeveelheden opgeteld, gegroepeerd per schap)
- Handmatig items toevoegen, afvinken, delen met huisgenoten (realtime sync)
- Aanbiedingen: backend-job (Edge Function / cron, dagelijks) haalt aanbiedingen op van Nederlandse supermarkten en matcht die met lijst-items. Toon per item de goedkoopste supermarkt en totale prijs per winkel. Bouw dit als losse "OfferProvider"-module zodat bronnen uitwisselbaar zijn. De app zelf scrapet nooit.
- Kies favoriete supermarkten en postcode

### 6. Sport & progressie
- Schema's: kant-en-klare schema's (Full body 3×, Upper/Lower 4×, PPL 6×) + eigen schema maken
- Oefeningendatabase met afbeelding/animatie, spiergroepen, instructies
- Training loggen: sets, reps, gewicht, RPE, rusttimer (met Live Activity)
- Progressieve overbelasting (double progression):
  - Elke oefening heeft een rep-range (bijv. 8–12)
  - Haal je bij alle sets de bovenkant van de range met RPE ≤ 8 → toon "Klaar om zwaarder te gaan: +2,5 kg" (compound) of +1–2 kg (isolatie)
  - 2 trainingen achter elkaar onder de onderkant → stel deload/gewicht terug voor
- Progressie: grafieken (Swift Charts) per oefening, geschatte 1RM (Epley), volume per spiergroep, PR's
- Lichaamsgewicht en omtrekmetingen + progressiefoto's (alleen lokaal/privé opgeslagen)
- Trainingen uit HealthKit verhogen het kcal-budget (instelbaar aan/uit)

### 7. Meertaligheid
- Start met Nederlands, Engels, Duits; uitbreidbaar
- Alle teksten via String Catalog, eenheden via Measurement/Locale (kg/lb, kcal/kJ)
- Productnamen tonen in taal van de gebruiker als Open Food Facts die heeft

## Non-functional
- Offline-first: loggen werkt zonder internet, sync later
- Privacy: AVG/GDPR-proof, data export (JSON/CSV), account verwijderen, privacyverklaring
- Toegankelijkheid: Dynamic Type, VoiceOver, donkere modus
- Supabase Row Level Security op alle tabellen
- Geen API-keys in de app; alle betaalde/geheime calls via Edge Functions
- Unit tests voor kcal/macro-berekening, wezentje-logica en progressie-regels

## Kwaliteit: GEEN AI slop (harde eis)

Code:
- Geen placeholders, TODO's, dummy-data of "// rest van de implementatie". Elke functie die je oplevert is af en werkt.
- Verzin geen API's, endpoints, packages of Swift-methodes. Twijfel je: zeg het en check de officiële documentatie.
- Geen overbodige abstracties, lege protocollen, managers-van-managers of boilerplate. Kies de simpelste oplossing die werkt.
- Geen commentaar dat herhaalt wat de code doet; alleen commentaar dat uitlegt waarom.
- Geen ongebruikte code, imports of bestanden.
- Pas als het compileert en de tests slagen mag je zeggen dat iets klaar is. Meld eerlijk wat niet werkt of nog ontbreekt.

Design:
- Geen generieke AI-look: geen paars-blauwe gradients overal, geen emoji als iconen, geen standaard glassmorphism-kaartjes. Gebruik SF Symbols, een eigen vast kleurpalet en consistente spacing volgens de Apple Human Interface Guidelines.
- Het wezentje en alle illustraties hebben één consistente, eigen stijl.
- Foto's van gerechten en producten zijn echte foto's (Open Food Facts, eigen foto's of een rechtenvrije bron), geen AI-gegenereerde voedselfoto's die niet kloppen met het recept.

Tekst:
- Korte, menselijke teksten in de app. Geen wollige marketingtaal ("Ontgrendel je volledige potentieel!") en geen uitroeptekens-spam.
- Vertalingen klinken natuurlijk, geen letterlijke vertaling uit het Engels.
- Kcal, macro's en trainingsadvies komen uit vaste formules en regels in de code, nooit uit verzonnen getallen.

## Fases
1. Projectopzet, auth (Apple/Google/e-mail), onboarding, doelberekening
2. Voeding loggen + barcode + Open Food Facts + dagoverzicht
3. Wezentje + widget + notificaties
4. Sport: schema's, loggen, progressie-advies, grafieken, HealthKit
5. Recepten + weekmenu
6. Boodschappenlijst + aanbiedingen-backend
7. Lokalisatie afronden, polish, TestFlight

Begin nu met: architectuurvoorstel, mappenstructuur, SwiftData-modellen en Supabase-schema (SQL). Wacht daarna op mijn akkoord.

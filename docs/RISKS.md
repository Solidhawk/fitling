# Fitling – risico's

Wat er mis kan gaan en hoe we het opvangen. "Vóór fase N" betekent: dit moet beantwoord zijn voordat die fase begint. Juridische punten kan een AI signaleren maar niet beslissen; die liggen bij jou of een jurist.

## Datakwaliteit

| Nr | Risico | Gevolg | Opvang |
|---|---|---|---|
| R-01 | **Open Food Facts is door vrijwilligers ingevuld.** Waarden ontbreken, staan per portie in plaats van per 100 g, of zijn fout overgetypt. | Verkeerde kcal in het dagtotaal, en dus een verkeerd wezentje. | Normaliseren en controleren in `lookup-product` (ARCHITECTURE §5.1): waarden buiten hun grens vervallen, en kcal die meer dan 25 % afwijkt van wat de macro's opleveren geeft "Controleer de waarden". Ontbrekend is `null`, nooit 0. De gebruiker kan een product corrigeren; dat wordt een eigen product en verandert de gedeelde rij niet ongezien. |
| R-02 | **Licentie van Open Food Facts (ODbL).** Wie de database gebruikt, moet de bron noemen; wie hem verrijkt en verspreidt, moet de verrijking onder dezelfde licentie delen. | Een juridisch probleem als we data mengen en als eigen database aanbieden. | Bronvermelding in de app (scherm "Over"). Elke rij houdt zijn `source`. We bieden onze cache niet aan derden aan. Terugsturen naar Open Food Facts is een aparte, uitdrukkelijke keuze van de gebruiker en wordt pas in fase 7 overwogen. Laat de voorwaarden lezen vóór de App Store. |
| R-03 | **NEVO (RIVM).** De tabel is vrij te raadplegen, maar hergebruik in een app heeft eigen voorwaarden. | Importeren zonder toestemming. | Vóór taak 2.9: de gebruiksvoorwaarden van NEVO-online lezen en zo nodig toestemming vragen. Zonder toestemming vervalt de import en blijven onverpakte producten eigen producten van de gebruiker. |
| R-04 | **Betaalde productbron (FatSecret, Nutritionix).** Kosten per aanroep, en voorwaarden die opslaan in een eigen cache vaak verbieden of beperken. | Onverwachte rekening of contractbreuk. | Staat uit. De pipeline werkt zonder. Aanzetten vraagt een contract, een maandbudget en een nieuwe blik op wat gecachet mag worden. De teller in `private.rate_limits` begrenst het aantal aanroepen per gebruiker. |

## App Store

| Nr | Risico | Gevolg | Opvang |
|---|---|---|---|
| R-05 | **HealthKit-review.** Apple wijst apps af die HealthKit-data voor iets anders gebruiken dan de gebruiker verwacht, die data in iCloud zetten, of geen duidelijke uitleg geven. | Afwijzing. | Alleen lezen (trainingen, stappen, actieve energie), met een uitleg in gewone taal bij de toestemming. De data blijft op het toestel (`DayActivity`) en gaat niet naar Supabase. De schakelaar "trainingen tellen mee" staat standaard uit. Privacyverklaring en App Privacy-labels moeten dit zo beschrijven. |
| R-06 | **Sign in with Apple.** Verplicht zodra er een andere inlog van derden is (Google); het token moet worden ingetrokken bij account verwijderen. | Afwijzing. | Beide zitten in het ontwerp. De knop van Apple staat bovenaan en is minstens zo groot als de andere. Het intrekken gebeurt in `delete-account`; dat is alleen met echte Apple-sleutels te testen (UNFORGET S1, TestFlight). |
| R-07 | **Account verwijderen moet in de app kunnen** en echt alles wissen. | Afwijzing; AVG-overtreding. | Alle tabellen hangen met `on delete cascade` aan de gebruiker; de pgTAP-test controleert dat. Bestanden in Storage (foto's van etiketten) moeten in fase 2 in dezelfde functie mee verwijderd worden: taak 2.8. |
| R-08 | **Meldingen van het wezentje.** Apple en gebruikers accepteren geen meldingen die schuld aanpraten of te vaak komen. | Uitgezette meldingen, slechte reviews, mogelijk afwijzing. | Hoogstens twee per dag, nooit 's nachts, instelbaar en uit te zetten. De teksten zijn vriendelijk en nooit beschamend; de toon kiest de gebruiker. |

## Privacy en AVG

| Nr | Risico | Gevolg | Opvang |
|---|---|---|---|
| R-09 | **Gezondheidsgegevens (art. 9 AVG):** gewicht, lengte, geslacht, voeding, trainingen. | Hoge eisen aan grondslag, beveiliging en bewaartermijnen. | Uitdrukkelijke toestemming als eerste stap, met tijdstip en versie. RLS op elke tabel, getest. Server in de EU (te kiezen bij het productieproject, UNFORGET S4). Privacyverklaring vóór er andere mensen de app gebruiken (UNFORGET S3). Data-export in fase 7. Geen analytics van derden. |
| R-10 | **Gedeelde boodschappenlijst** laat data tussen gebruikers stromen. | Een huisgenoot ziet meer dan bedoeld. | Leden zien alleen de lijst, de items en elkaars opgegeven naam. Lid worden kan alleen met een code die zeven dagen geldt. De eigenaar kan leden verwijderen. Getest in pgTAP, inclusief "wie weg is, komt niet zelf terug". |
| R-11 | **Voortgangsfoto's** zijn het gevoeligste wat de app aanraakt. | Lekken is onherstelbaar. | Ze verlaten het toestel niet, staan in de eigen map van de app en zitten niet in de iCloud-backup (taak 4.10 zet de vlag `isExcludedFromBackup`). |
| R-12 | **Eetgedrag.** Een app die calorieën telt en een wezentje laat reageren, kan ongezond gedrag versterken. | Schade bij kwetsbare gebruikers. | Nooit een voorstel onder BMR × 1,1. Te weinig eten geeft geen XP en geen slankere vorm. Half gelogde dagen tellen niet als te weinig. Het wezentje gaat nooit dood en elke toestand heeft een weg terug. Minimumleeftijd 18. Bij een doel onder de gangbare ondergrens staat een verwijzing naar arts of diëtist. Dit is geen medisch hulpmiddel; de teksten mogen dat ook niet suggereren. |

## Aanbiedingen

| Nr | Risico | Gevolg | Opvang |
|---|---|---|---|
| R-13 | **Voorwaarden van supermarkten.** Hun websites verbieden meestal geautomatiseerd uitlezen; folders en prijzen kunnen onder het databankenrecht vallen. | Een sommatie, of geblokkeerde toegang. | **Vóór fase 6 beslissen** welke bron mag: een officiële API, een partner die de data levert, of uitdrukkelijke toestemming. Tot dan bestaat alleen een provider met testdata. De `OfferProvider`-interface maakt wisselen één bestand werk. Zonder bron vervalt het onderdeel en blijft de lijst zonder prijzen bruikbaar. |
| R-14 | **Een verkeerde match** laat een prijs zien bij het verkeerde product. | De gebruiker rijdt naar de verkeerde winkel. | Alleen een barcode of een volledige naam is "zeker". Al het andere staat er als "mogelijk" en telt niet mee in de totalen tot de gebruiker het bevestigt (ARCHITECTURE §6.1). De app verzint nooit een prijs voor iets wat niet in de aanbieding is. |

## Techniek

| Nr | Risico | Gevolg | Opvang |
|---|---|---|---|
| R-15 | **Geen Mac.** Bouwen en testen kan alleen in GitHub Actions, met ongeveer 190 Mac-minuten per maand. Deze maand is daarvan naar schatting meer dan de helft gebruikt. | Een bouwfout kost een run van vijf minuten; op is op tot de volgende maand. | Alles wat kan in FitlingCore (Linux, gratis). Mac-runs alleen met `[ios]` in het commitbericht, gebundeld per taak. TASKS.md zegt per taak of een Mac-run nodig is. Bij een tekort: wachten, of minuten bijkopen. |
| R-16 | **Niets is op een echt toestel getest.** Inloggen met Apple en Google, de links in e-mails, pushmeldingen, widgets, HealthKit en de camera werken niet of anders in de simulator. | Fouten die pas bij TestFlight blijken. | TestFlight uiterlijk vóór fase 3 (UNFORGET S1). Tot dan zijn deze onderdelen "gebouwd, niet bewezen" en zo benoemd in TASKS.md. |
| R-17 | **Klok van het toestel.** Sync beslist op `updated_at` van de client. | Een toestel met een verkeerde klok overschrijft nieuwere data. | De server zet een tijd uit de toekomst terug naar zijn eigen tijd. Een klok die achterloopt, verliest alleen zijn eigen wijziging; die blijft lokaal zichtbaar tot de pull. Getest in pgTAP. |
| R-18 | **SwiftData is jong** (iOS 17). Gedrag bij migraties en bij veel rijen is minder uitgekristalliseerd dan Core Data. | Dataverlies bij een schema-wijziging na de eerste release. | Alle modellen staan in `FitlingSchemaV1`; elke latere wijziging is een `V2` met een migratiestap en een test. Vóór de eerste release mag V1 nog veranderen. Woordenboeken staan als JSON in `Data` omdat dat zeker werkt. |
| R-19 | **Het gratis Supabase-project** pauzeert na een week zonder gebruik en de ingebouwde mail stuurt alleen naar teamleden. | Inloggen en mails werken niet voor testers. | Eigen SMTP en een betaald of actief project vóór TestFlight (UNFORGET S2 en S4). |
| R-20 | **De afstelling van het wezentje** (drempels, XP, levels) is bedacht, niet gemeten. | Te streng of te makkelijk; het motiveert niet. | De getallen staan als benoemde constanten in `CreatureEngine` met tests. Bijstellen na de eerste weken echt gebruik is een taak voor Fable (TASKS 3.9). |

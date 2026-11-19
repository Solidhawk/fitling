---
version: 1
slug: "fitling"
primary_target: "Fitling"
related_targets: []
---

## Scope

Fitling iOS-app (SwiftUI), mode: operate. Fase 1: welkom/inloggen, onboarding, dagdoel, profiel en account. Later: dagoverzicht, loggen, partner, training, recepten, boodschappen.

## Audience and task

Beginners en fanatieke sporters, even zwaar (PRODUCT.md). Voorbeelden die de gebruiker mooi vindt: Finch, Duolingo. Gevraagd: eigen en gewaagd. De vorige richting (De Stijl) is afgewezen als "grafisch slecht" (2026-11-18).

## Direction contract

THESIS: Je partner is een verzamelfiguur met een eigen kaart: naam, startdatum, één zin karakter en een lintkleur per soort; je eten en training kleuren dat lint. Weigert zowel het koele cijferdashboard als de generieke cartoon-app.

OWN-WORLD: Zachte pastelgrond (licht lila; donker diep pruim), witte kaarten met ronde hoeken; partners mollig en rond met stompe voetjes, kleine ogen, glans en schaduw als vlakke tinten binnen het lijf en een schaduw op de grond (2026-11-19: variant B gekozen, geen stickerrand). Geen verloop. Eén verzadigde lintkleur per soort: Sprout groen, Ember oranje, Pip geel, Pebble blauwgrijs; macro-linten koraal (eiwit), zonnebloem (koolhydraten), hemelsblauw (vet), altijd met inkttekst. Ronde vette letter (SF Rounded), Heavy voor namen en getallen. Actieve cel neemt zijn lintkleur, uitgeschakeld drukt in grijs.

STORY: Je kiest een figuur, geeft het een naam, en ziet elke dag als een kaart waarvan de linten zich vullen; de getallen blijven strak en verklaarbaar.

FIRST VIEWPORT: Welkom: catalogusraster van de vier figuren (Sprout, Ember, Pip, Pebble), elk op een pastelkaart met naamplaatje en één zin karakter; titel en tagline erboven; inloggen onderaan binnen duimbereik. Dagdoel: één kaart met naamplaatje "Per dag", kcal groot in Heavy, drie macro-linten met grammen; "Aanpassen" in de werkbalk.

FORM: Karaktercatalogus (character goods catalog), gekozen door de gebruiker in ronde 3 (gewaagd register). seed:85781bc101b842ef

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## Constraints

- HIG: systeemnavigatie, Dynamic Type, SF Symbols, 44 pt tikvlakken; Sign in with Apple blijft de systeemknop (ronde hoeken passen in deze wereld).
- Partners zijn vector (SwiftUI-vormen), geen rasters, geen AI-beelden; één vaste stijl: mollig lijf, vlakke tinten voor licht en schaduw (geen verloop), kleine ogen met glimlicht, grondschaduw. Stijlvoorbeeld van de gebruiker: een vrolijk, rond kaartspel-personage; alleen als stijl gebruikt, niet nagetekend.
- Kcal-ring uit PROMPT.md (fase 2) volgt deze wereld: lintkleur, ronde kapjes, geen verloop.
- Build path: code-led (operate).

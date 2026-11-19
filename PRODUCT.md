# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Users

Twee groepen, even zwaar (bevestigd 2026-11-18):
- **Beginners** die gezonder willen eten en trainen en motivatie en uitleg nodig hebben.
- **Fanatieke sporters** die al trainen en macro's tellen en snel en precies willen loggen.

De app neemt beginners mee zonder sporters af te remmen. Situatie: kort en vaak gebruik op de telefoon, rond maaltijden, in de supermarkt en in de sportschool (tussen sets).

## Product Purpose

Fitling combineert voeding loggen, trainen, recepten en weekmenu, en boodschappen met Nederlandse supermarktaanbiedingen in één app. Een eigen partner reageert op hoe je eet en traint. Succes: mensen blijven loggen, halen hun kcal- en eiwitdoel en trainen met progressie, zonder schuldgevoel.

## Positioning

Beide samen (bevestigd): de partner is het gezicht van de app; de alles-in-één-aanpak voor Nederland (voeding, training, weekmenu, boodschappen met aanbiedingen) is de reden om te blijven. Een losse calorieteller of trainingslogger heeft geen van beide.

## Operating Context

- Loggen: barcode scannen, zoeken, recent/favoriet, porties; vaak met één hand en snel.
- Trainen: sets, reps, gewicht, RPE en rusttimer tussen sets; Live Activity op het vergrendelscherm.
- Plannen: weekmenu en boodschappenlijst, gedeeld met huisgenoten.
- De partner op het beginscherm (widget) en in pushmeldingen.

## Capabilities and Constraints

- Native iOS 17+, Swift 6, SwiftUI, SwiftData, Supabase. Offline-first.
- Fases en specificatie: `PROMPT.md`; architectuur: `docs/superpowers/specs/2026-11-18-fitling-architectuur-design.md`.
- Talen: Nederlands (bron), Engels, Duits; eenheden via Locale (kg/lb, kcal/kJ).
- Minimumleeftijd 18. Gezondheidsgegevens alleen met expliciete toestemming (AVG art. 9).
- Kcal, macro's en trainingsadvies komen uit vaste formules en regels, nooit uit verzonnen getallen.

## Brand Commitments

- "Fitling" is een **werktitel**; vormgeving en icoon mogen niet op de naam leunen.
- Teksten kort en menselijk; geen wollige marketingtaal, geen uitroeptekens-spam; vertalingen klinken natuurlijk.
- Partner en illustraties: één consistente, eigen stijl. Vriendelijk, nooit beschamend; herstel altijd mogelijk.
- Geen generieke AI-look: geen paars-blauwe gradients, geen glassmorphism-kaartjes, geen emoji als icoon. SF Symbols en Apple HIG.
- Foto's van eten zijn echt (Open Food Facts, eigen foto's, rechtenvrij), nooit AI-gegenereerd.

## Partner (bevestigd 2026-11-18, bouw in fase 3)

In alles wat de gebruiker leest heet hij "je partner", nooit "wezentje" (bevestigd 2026-11-19). Stijl: mollig en rond, stompe voetjes, kleine ogen, licht en schaduw als vlakke tinten, geen rand (variant B, 2026-11-19).

Setup, vier keuzes:
1. **Soort:** Sprout, Ember, Pip of Pebble.
2. **Naam:** door de gebruiker verzonnen.
3. **Kleur:** drie varianten per soort; later meer vrij te spelen, plus accessoires (bijv. hoedje, sjaal).
4. **Toon van de meldingen:** lief, grappig of coach. Voorbeelden van de gebruiker voor "honger": lief "Ik heb honger 🥺", grappig "Mijn maag knort harder dan jouw wekker", coach "Tijd voor eiwit. Wat eet je?". Emoji mogen in meldingteksten (keuze van de gebruiker), nooit als icoon.

Regels die het motiverend houden:
- De partner reageert op het gemiddelde van de afgelopen 7 dagen; één zware dag verandert de vorm niet meteen.
- Een training telt als bonus, zichtbaar per soort: bij Ember wordt de vlam feller, bij Sprout komt er een bloem bij.
- Herstel wordt beloond: na een week van "te veel" terug naar "fit" levert extra XP op.
- Een slapende partner wordt wakker van één gelogde maaltijd.

## Evidence on Hand

Geen: nog geen logo, foto's, gebruikersonderzoek of testimonials. Niets daarvan mag verzonnen worden.

## Product Principles

1. Nooit beschamen: elke status heeft een vriendelijke weg terug.
2. Snel voor wie het kent, duidelijk voor wie begint: uitleg op aanvraag, niet in de weg.
3. Getallen zijn te verklaren: elke berekening kan laten zien waar hij vandaan komt.
4. Offline werkt alles wat loggen is.
5. Privacy is standaard: alleen wat nodig is, met toestemming.

## Accessibility & Inclusion

Dynamic Type tot de grootste toegankelijkheidsmaten, VoiceOver op elk bedieningselement, donkere modus, tikvlakken van minimaal 44 pt, contrast minimaal WCAG AA. Geslacht kent ook "anders".

# Zestien 3D-partners inbouwen

**Doel:** de vier getekende partners (Sprout, Ember, Pip, Pebble) vervangen door de zestien 3D-partners uit `design/partners/nieuw/`, elk in zes vormen, met stemming, vorm (slank ↔ rond), kleur, accessoires en beweging. Akkoord van de gebruiker: 2026-11-20 ("Ja, begin met stap 1").

**Aanpak:** gelaagde afbeeldingen, gestapeld in SwiftUI. Per soort en vorm:

- `body.png`: het figuur zonder gezicht, met contactschaduw;
- `face-<mood>.png`: zes stemmingen;
- `item-<item>.png`: zes accessoires plus de zweetband na een training.

Alle lagen komen uit één camera en één schaal, zodat ze pixelgelijk op elkaar liggen. `anchors.json` geeft per soort en vorm de top en het midden van het hoofd (voor de Z's als hij slaapt).

- **Kleurvarianten:** een tintverschuiving op alleen `body.png`.
- **Lichaamsvorm:** horizontaal schalen van de hele stapel.
- **Beweging:** zoals nu (`PartnerMotion`).

## Taken

1. **Lagen renderen** (3D-agent): `design/partners/lagen/<species>/<form>/…` en `anchors.json`. Contract: zie het bericht aan de agent, en dit document.
2. **FitlingCore:**
   - `Species` krijgt 16 cases: bumblebee, mole, frog, owl, hedgehog, snail, axolotl, seal, penguin, turtle, rabbit, raccoon, ladybird, octopus, squirrel, lamb.
   - `growthLevels` wordt `[1, 3, 6, 10, 15, 22]`, dus stadium 0…5.
   - Tests: `growthStageFollowsLevel`, `sixteenSpecies`.
3. **Database:** de check op `creatures.species` in `schema.sql`, plus een pgTAP-test die een nieuwe soort accepteert en een oude weigert.
4. **Teksten:** naam en karakterregel per soort, in nl, en en de (`creature.<species>.name` en `.note`). De oude sleutels gaan weg.
5. **Kleuren:** een lintkleur en een tint per soort, als named colors in `Assets.xcassets/Partners/`.
6. **Afbeeldingen:**
   - Het script `scripts/partner-assets.py` zet de lagen in `Fitling/Resources/Partners.xcassets`, met naam `partner-<species>-<form>-<layer>` en lossy compressie.
   - `PartnerLayers` geeft de namen.
   - Test: elke combinatie bestaat in de bundle.
7. **Tekening:**
   - `PartnerCanvas` gaat de lagen stapelen en `PartnerDrawing.swift` (vectortekening) verdwijnt.
   - `FigureTests` worden tests op `PartnerLayers`: welke lagen er zijn per look, de volgorde, de kleurverschuiving en de breedte.
8. **Schermen:**
   - Partner kiezen: een raster van 16.
   - Welkomstscherm: een catalogus van 16.
   - De galerij voor de UI-test met alle soorten.
   - `PartnerGalleryTests` en `OnboardingFlowTests` worden bijgewerkt.
9. **Afronden:** DESIGN.md (sectie Partner Drawing), TASKS 3.3, UNFORGET S16, en CI groen.

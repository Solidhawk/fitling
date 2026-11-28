# Onverpakte producten uit NEVO

Groente, fruit, vlees, brood en andere producten zonder barcode komen uit het Nederlands Voedingsstoffenbestand
(NEVO-online versie 2025/9.0) van het RIVM: 2328 producten met een Nederlandse en een Engelse naam (TASKS 2.9,
UNFORGET S15). Ze staan als gedeelde rijen in `public.products`, met `source = 'nevo'`, de NEVO-code als `source_id`
en `is_verified = true`. Zoeken vindt ze zoals elk ander gedeeld product.

## Voorwaarden

De gebruiker ging op 2026-11-28 akkoord met de voorwaarden bij de download
(https://www.rivm.nl/nederlands-voedingsstoffenbestand/gebruik-nevo-online/download-bestand):

- Alleen ongewijzigd en met de bron: "NEVO-online versie 2025/9.0, RIVM, Bilthoven". Daarom blijven de namen zoals
  NEVO ze schrijft ("Appel z schil gem"), en staat de vermelding in "Over Fitling" (`account.about.nevo`).
- Aanvullingen mogen, als duidelijk is dat ze niet van NEVO zijn. De import voegt alleen zout toe, berekend uit natrium
  (× 2,5, EU-verordening 1169/2011), en een zoeksleutel.
- Gebruikers betalen nooit voor het gebruik van de NEVO-gegevens.
- Komt er een nieuwe versie, dan vervangt die de oude (zie hieronder).

De tabel en de SQL daaruit staan niet in git: de repository is openbaar. CI test de import met verzonnen producten
(`scripts/fixtures/nevo-test.csv`, `supabase/tests/nevo_import_test.sql`).

## Op het echte project zetten

1. Download het bestand via de link hierboven (akkoord met de voorwaarden) en pak `NEVO2025_v9.0.csv` uit.
2. Maak de SQL, in de map van het project:

   ```sh
   node scripts/nevo-import.mjs <pad naar NEVO2025_v9.0.csv>
   ```

   Dat schrijft `supabase/seed/nevo.sql` (in `.gitignore`).
3. Voer die SQL uit op het project, bijvoorbeeld:

   ```sh
   supabase db query --remote=<project-ref> -f supabase/seed/nevo.sql
   ```

   Het is één transactie, en opnieuw uitvoeren kan. Elk product krijgt een vaste id uit zijn NEVO-code, dus
   favorieten en gelogde producten blijven bij een nieuwe versie kloppen.

## Een nieuwe versie

Het script weigert een tabel van een andere versie. Pas dan `VERSION` en `REFERENCE` in `scripts/nevo-import.mjs` aan,
en de tekst `account.about.nevo` in nl, en en de. Producten die niet meer in de nieuwe tabel staan, krijgen
`deleted_at`; een product dat terugkomt, wordt weer zichtbaar.

# Zoeken in de gedeelde producten (search-products)

Zoeken vindt elk woord in elke volgorde, met de beste treffer eerst. "halfvolle melk" vindt NEVO's "Melk halfvolle", en
"appel" geeft eerst de appel en pas daarna "Aardappelen". De volgorde is overal dezelfde:

- de iPhone en de browser gebruiken `FoodLog.bestMatches` in FitlingCore;
- de server gebruikt `public.search_products` in `supabase/search-products.sql`.

Eerst komt het woord zelf als eerste woord van de naam. Dan volgt een naam die ermee begint, en daarna namen waarin meer
woorden een woord beginnen. Daarna komen nagekeken producten (NEVO), en als laatste telt de kortste naam.

## Op het echte project zetten, vóór de merge

De site op GitHub Pages wordt bij elke merge naar main gebouwd en praat met het echte project. Zonder de functie
geeft elk zoeken van drie tekens of meer een fout op de site, en vindt de iPhone online niets. Daarom gaat het in deze
volgorde:

1. Supabase → SQL Editor: plak de inhoud van `supabase/search-products.sql` en voer het uit. Het kan ook met
   `supabase db query --remote=<project-ref> -f supabase/search-products.sql`. Opnieuw uitvoeren kan, en een oudere
   versie van de app merkt er niets van.
2. Controleer het: `select search_name from public.search_products('melk');` geeft rijen, met de beste eerst.
3. Merge daarna pas de PR.

Na `supabase/reset-dev.sql` moet dit bestand opnieuw, net als `schema.sql`, `web-push.sql` en `submit-product.sql`.

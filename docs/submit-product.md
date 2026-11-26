# Een product delen (submit-product)

Een eigen product met een barcode die nergens bekend is, kan de gebruiker delen. Dan vindt iedereen het als hij die
barcode scant, met de vraag de waarden te controleren (TASKS 2.8, ARCHITECTURE §5 stap 3). Zonder deze stappen werkt
alles behalve het delen; een eigen product blijft dan alleen van de gebruiker.

## Op het echte project zetten

1. Supabase → SQL Editor: plak de inhoud van `supabase/submit-product.sql` en voer het uit. Opnieuw uitvoeren kan.
2. In een terminal in de map van het project:

   ```sh
   supabase functions deploy submit-product
   ```

   De functie gebruikt dezelfde geheimen als `lookup-product` (`SUPABASE_URL`, `SUPABASE_SECRET_KEYS`); die zet
   Supabase zelf.

## Wat er gebeurt

| Moment | Wat |
|---|---|
| Eerste inzending voor een barcode | Wordt de gedeelde rij: `source = 'user'`, nooit geverifieerd. De inzending zelf blijft bewaard (`product_submissions`), met alleen de velden die de app stuurt. |
| Een volgende inzending | De rij blijft zoals hij is en de inzending wacht. Alleen wie de rij maakte, mag hem verbeteren. |
| Een weggehaalde gedeelde rij | Komt terug met de waarden van de nieuwe inzending. |
| Open Food Facts kent het product later wel | `lookup-product` vraagt Open Food Facts eerst; dat antwoord vervangt de rij van de gebruiker. |
| Grenzen | Twintig inzendingen per gebruiker per uur. De barcode moet echt zijn, de energie tussen 0 en 900 kcal; andere waarden buiten hun grens worden leeg. |
| Account verwijderen | De inzendingen gaan mee (`on delete cascade`); een gedeelde rij blijft, want die is van iedereen. |

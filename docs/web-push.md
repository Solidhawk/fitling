# Web Push: de herinneringen van de partner in de webversie

Op de iPhone stuurt de partner hoogstens twee herinneringen per dag, nooit tussen 21:00 en 08:00. De app doet dat met lokale meldingen. De webversie kan dat niet zelf: een browser plant geen meldingen. Daarom zijn er twee delen:

- De browser plant de berichten van vandaag en morgen, met dezelfde regels als de app (`ReminderPlanner` in FitlingCore). Het plan gaat naar de tabel `push_reminders`.
- De Edge Function `send-reminders` stuurt elke minuut wat aan de beurt is naar de pushdienst van de browser: Apple, Google, Mozilla of Microsoft.

Zonder de stappen hieronder werkt de webversie gewoon, alleen zonder herinneringen. De sectie Herinneringen op het tabblad Partner verschijnt pas als de webversie met de publieke sleutel gebouwd is (stap 6).

Alle stappen gebeuren één keer per project. Geheimen komen nooit in de code of in een chat.

## 1. Het sleutelpaar maken

Op je eigen computer, in de map van het project (Deno staat er al):

```powershell
deno run supabase/functions/send-reminders/vapid-keys.ts
```

Het script drukt twee regels af: `VAPID_PUBLIC_KEY=…` en `VAPID_PRIVATE_KEY=…`. Bewaar ze in je wachtwoordbeheerder.

- De **private** sleutel is geheim. Die gaat alleen naar de secrets van Supabase (stap 3).
- De **publieke** sleutel mag iedereen zien. Die gaat ook naar GitHub (stap 6).

Maak het paar maar één keer. Met een nieuw paar moet elke browser zich opnieuw aanmelden: herinneringen uit en weer aan.

## 2. De tabellen

Supabase → SQL Editor. Plak de inhoud van `supabase/web-push.sql` en voer het uit.

Dit maakt alleen `push_subscriptions` en `push_reminders` met hun regels. Bestaande data blijft. Opnieuw uitvoeren kan.

## 3. De geheimen van de functie

Supabase → Edge Functions → Secrets. Voeg er twee toe:

| Naam | Waarde |
|---|---|
| `VAPID_PUBLIC_KEY` | de publieke sleutel uit stap 1 |
| `VAPID_PRIVATE_KEY` | de private sleutel uit stap 1 |

## 4. De functie zetten

In de map van het project:

```powershell
supabase functions deploy send-reminders
```

De functie controleert zelf de geheime sleutel van het project. Daarom staat `verify_jwt = false` in `supabase/config.toml`, net als bij `sync-offers`.

## 5. Elke minuut versturen

De twee geheimen in Vault heb je al voor de aanbiedingen (`sync-offers-cron.sql`): `fitling_project_url` en `fitling_secret_key`. Ontbreken ze, maak ze dan aan zoals bovenin `supabase/sync-offers-cron.sql` staat.

Supabase → SQL Editor. Plak de inhoud van `supabase/send-reminders-cron.sql` en voer het uit. Er komt één job `send-reminders` bij, die elke minuut kijkt of er iets klaarstaat. Alleen dan roept hij de functie aan.

## 6. De webversie met de publieke sleutel bouwen

GitHub → het project → Settings → Secrets and variables → Actions → Variables. Voeg toe:

| Naam | Waarde |
|---|---|
| `VAPID_PUBLIC_KEY` | de publieke sleutel uit stap 1 |

De volgende bouw van `main` zet de site met de sectie Herinneringen.

## 7. Proberen op de iPhone

Web Push werkt op een iPhone vanaf iOS 16.4, en alleen in een app op het beginscherm.

1. Open de site in Safari en tik op Delen → Zet op beginscherm.
2. Open Fitling vanaf het beginscherm en log in.
3. Ga naar Partner → Herinneringen → Herinneringen sturen. iOS vraagt of Fitling meldingen mag sturen: Sta toe.
4. Zet een tijd een paar minuten vooruit. Binnen een minuut na die tijd komt de melding.

Komt er niets? Kijk in Supabase → Edge Functions → send-reminders → Logs.

- Een 403 van de pushdienst: het sleutelpaar in stap 3 hoort niet bij de publieke sleutel in stap 6.
- `misconfigured`: er ontbreekt een geheim uit stap 3.

## Wat er gebeurt

| Moment | Wat |
|---|---|
| Herinneringen aan | De browser vraagt toestemming, meldt zich aan bij zijn pushdienst en zet het adres in `push_subscriptions`, via `save_push_subscription`. |
| Vandaag of de partner openen, een tijd wijzigen | De browser plant opnieuw voor vandaag en morgen en vervangt de rijen in `push_reminders`, via `replace_push_reminders`. Dat zijn er hoogstens vier. |
| Elke minuut | `send-reminders` versleutelt elk bericht dat aan de beurt is voor die ene browser (RFC 8291) en stuurt het met de VAPID-handtekening (RFC 8292). |
| Bericht te laat (meer dan 30 minuten) | Het wordt niet meer verstuurd, zodat er nooit een lunchbericht 's nachts komt. |
| Browser afgemeld (404/410) | Het abonnement en de herinneringen gaan weg. |
| Uitloggen | Het abonnement van deze browser gaat weg, met de herinneringen. |

De functie belt alleen de pushdiensten van Apple, Google, Mozilla en Microsoft, nooit een ander adres.

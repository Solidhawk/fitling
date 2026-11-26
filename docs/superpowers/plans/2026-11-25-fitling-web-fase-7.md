# Fitling web fase 7: Beginscherm en afronden — implementatieplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** de webversie af als app op het beginscherm van een iPhone:
- icoon en manifest;
- openen en loggen zonder verbinding;
- de herinneringen van de partner via Web Push, zoals de lokale meldingen op iOS;
- een laatste ronde vormgeving.

**Architecture:**
- **Service worker** (`web/public/sw.js`, met een lijst bestanden die de bouw invult). Deze houdt de app en de rekenregels op het toestel en raakt verzoeken aan Supabase nooit aan.
- **Zonder verbinding:**
  - Lezen gaat via een momentopname in IndexedDB van wat Vandaag en het opstarten nodig hebben.
  - Schrijven gaat via een wachtrij ("outbox") in IndexedDB. Die stuurt de rij later precies zo op als hij gemaakt is: zelfde id, zelfde `updated_at`. Zo blijft het sync-contract heel; laatste schrijver wint op de server.
- **Herinneringen:**
  - `ReminderPlanner` verhuist naar FitlingCore.
  - De browser plant met de regels van iOS en zet het plan als rijen in `push_reminders`.
  - Een Edge Function `send-reminders` stuurt wat aan de beurt is, via Web Push (VAPID, RFC 8291), aangeroepen door pg_cron.
  - Alles staat achter `VITE_VAPID_PUBLIC_KEY`. Zonder die sleutel ontbreekt het onderdeel, zoals de Google-knop.

**Tech Stack:** Swift 6 (FitlingCore, WASM-brug), React 18 + TypeScript, IndexedDB, Service Worker, Web Push, Supabase (Postgres, pg_cron, pg_net, Edge Functions in Deno), Vitest, Playwright, pgTAP.

**Spec:** `docs/superpowers/specs/2026-11-24-fitling-web-design.md` (fase 7). Advies van Fable 5.2 (2026-11-25) is hierin verwerkt.

## Global Constraints

- **Paden:** alles onder `/fitling/`, via `import.meta.env.BASE_URL`. Het manifest heeft `start_url`, `scope` en `id` = `/fitling/`, en de service worker staat op `/fitling/sw.js`.
- **Versies:** de rekenregels en de webcode horen bij dezelfde bouw. De WASM krijgt het bouwnummer in zijn adres. `index.html` komt eerst van het netwerk, en pas zonder verbinding uit de cache.
- **Geheimen:** de geheime VAPID-sleutel komt nooit in de code. Alleen de publieke sleutel gaat als GitHub-variabele in de bouw.
  - Wat op het echte project moet (schema, functie, secrets, cron), bereid ik voor met precieze stappen. De gebruiker voert het uit.
- **Teksten:** geen hardcoded teksten. Nieuwe sleutels gaan in `Localizable.xcstrings`, nl/en/de, achteraan toegevoegd.
- **Afbeeldingen:** het icoon komt uit eigen werk: de 3D-partners, Blender-renders van dit project. Geen AI-beeld en geen emoji. Het is voorlopig; de gebruiker keurt het (S37).
- **Tests:** Playwright-tests die `page.route` gebruiken, blokkeren de service worker. Een eigen project test de service worker en het offline gedrag.

## Review Focus

- **Een maaltijd die zonder verbinding gelogd is,** staat er na verbinden precies één keer, ook na herladen tijdens het versturen. Test in Task 3 (`offlineLogArrivesOnce`).
- **Een oude service worker of cache** mag nooit oude rekenregels met nieuwe code mengen. Test in Task 2 (`theCoreFollowsTheBuild`).
- **Herinneringen:** hooguit twee per dag, nooit tussen 21:00 en 8:00, voor vandaag en morgen, met de tekst die iOS kiest. Test in Task 4 (`ReminderPlannerTests`, ongewijzigd van iOS overgenomen).
- **Push-versleuteling** volgt RFC 8291 bit voor bit. Test in Task 5 (RFC-testvector).
- **Een abonnement of plan** van een andere gebruiker is niet te lezen of te wijzigen. Test in Task 5 (pgTAP).

---

### Task 1: Icoon, manifest en meta

**Files:** Create:
- `design/icoon/maak_icoon.py`: zet een partner (uil, vorm 1, blij) uit de lagen van `Fitling/Resources/Partners.xcassets` met `PartnerAnchors.json` op de grond, zonder tekst;
- `web/public/icons/` (`apple-touch-icon.png` 180, `icon-192.png`, `icon-512.png`, `icon-maskable-512.png`, `favicon-32.png`);
- `web/public/manifest.webmanifest`.

Modify `web/index.html`: manifest, apple-touch-icon, `theme-color` voor licht en donker, `apple-mobile-web-app-capable`, title en `lang`.

- [ ] Rood: `scripts/generate.test.mjs` → `theManifestPointsAtTheIcons`: het manifest is geldig, de iconen bestaan en zijn PNG van de juiste maat, en paden staan onder `/fitling/`.
- [ ] Bouwen.
- [ ] CI groen.

### Task 2: Service worker voor de app

**Files:**
- Create `web/public/sw.js`.
- Modify:
  - `web/vite.config.ts`: een plugin die na de bouw de bestandslijst en het bouwnummer in `dist/sw.js` zet;
  - `web/src/main.tsx`: registreren, alleen in een gebouwde app;
  - `web/src/core/useCore.ts`: de WASM met het bouwnummer in het adres;
  - `web/playwright.config.ts`: de bestaande projecten met `serviceWorkers: "block"`, plus een project `offline` in WebKit en Chromium.
- Create `web/e2e/offline.spec.ts`.

- [ ] Rood: `theAppOpensWithoutAConnection` (de shell en de rekenregels komen uit de cache) en `theCoreFollowsTheBuild` (een nieuwe bouw haalt nieuwe rekenregels).
- [ ] Bouwen: precache van shell en WASM. Runtime cache-first voor partners, oefeningen en recepten. Cross-origin nooit. Oude caches weg bij activeren.
- [ ] `navigator.storage.persist()` in de app.
- [ ] CI groen.

### Task 3: Loggen zonder verbinding

**Files:**
- Create `web/src/data/offline.ts`:
  - `snapshot` (lezen: laatste antwoord per sleutel);
  - `outbox` (wachtrij: tabel, soort, volledige rij, op volgorde);
  - `flush(client)`: FIFO; een insert die 23505 geeft telt als gelukt.
- Modify:
  - `web/src/data/diary.ts`: `logProduct`, `addWater`, `deleteEntry` en `setFavorite` schrijven via de wachtrij zonder verbinding. `entriesOn`/`waterOn` voegen wachtende rijen toe.
  - `web/src/data/profile.ts`, `profileStore.ts`, `creature.ts`: lezen met momentopname.
  - `App.tsx`: met momentopname geen "Geen verbinding" bij het opstarten.
  - `Day.tsx`: een rustige regel zolang er iets wacht. De nieuwe sleutel is `day.pending`.
- Tests: `web/src/data/offline.test.ts` (volgorde, idempotent, samenvoegen) en `e2e/offline.spec.ts` (`offlineLogArrivesOnce`).
- Herschrijf `log.spec.ts:125,140`: een afgebroken schrijfactie komt nu in de wachtrij.

- [ ] Rood.
- [ ] Bouwen.
- [ ] CI groen.

### Task 4: Herinneringen in FitlingCore en op het tabblad Partner [ios]

**Files:**
- Create `Packages/FitlingCore/Sources/FitlingCore/ReminderPlanner.swift`: `ReminderSettings`, `PlannedReminder` en `ReminderPlanner`, uit `Fitling/Services/PartnerReminders.swift`. Tests in `ReminderPlannerTests.swift`, overgenomen uit `PartnerTests`.
- Modify:
  - `PartnerReminders.swift` (iOS gebruikt de kern);
  - brug `remindersPlan({settings, tone, now, utcOffsetSeconds, topics})`;
  - `web/src/screens/Partner.tsx`: de sectie Herinneringen zoals `PartnerTabView`, alleen met `VITE_VAPID_PUBLIC_KEY`.
- Create `web/src/data/push.ts`: abonneren, het plan als rijen in `push_reminders` zetten (vervangen per toestel), opruimen bij uitloggen.
- Uitbreiding `sw.js`: `push` en `notificationclick`.

- [ ] Rood: `ReminderPlannerTests` in de kern, `remindersFollowTheCore` in de brug, en een e2e met een nagebootste `PushManager`.
- [ ] Bouwen.
- [ ] CI groen, ook iOS.

### Task 5: Versturen: schema, Edge Function, cron

**Files:**
- Modify `supabase/schema.sql` en `reset-dev.sql`: `push_subscriptions(id, user_id, endpoint unique, p256dh, auth, created_at)` en `push_reminders(id, user_id, subscription_id, fire_at, title, body)`. RLS op eigen rijen, echte deletes, geen sync-trigger. Ook `export.ts`.
- Create:
  - `supabase/tests/push_test.sql` (pgTAP);
  - `supabase/functions/send-reminders/index.ts` (secret-key check, VAPID ES256-JWT, RFC 8291 aes128gcm met WebCrypto, toegestane push-hosts, 404/410 verwijdert het abonnement, in porties);
  - `send-reminders/test.ts` (RFC 8291-testvector, ontsleutelen, JWT, injected fetch);
  - `supabase/send-reminders-cron.sql`.
- Create `docs/web-push.md`: de stappen voor de gebruiker (VAPID-paar maken, secrets, deploy, cron, GitHub-variabele).

- [ ] Rood.
- [ ] Bouwen.
- [ ] CI Supabase groen.

### Task 6: Vormgeving, audit, review, PR

- [ ] impeccable critique en audit over alle webschermen, met nl, en en de.
- [ ] Tikvlakken minstens 44 (S40).
- [ ] Borden naast iOS.
- [ ] Eindreview door Fable 5.2; Important fixen.
- [ ] UNFORGET.
- [ ] PR web-fase-7 → web-fase-6.

-- Verstuurt elke minuut de herinneringen van de webversie die aan de beurt zijn (web fase 7, docs/web-push.md).
--
-- Eenmalig per project, in de SQL Editor, nadat web-push.sql is uitgevoerd en send-reminders is gedeployd. Gebruikt
-- dezelfde twee geheimen in Vault als sync-offers-cron.sql: fitling_project_url en fitling_secret_key.
-- De functie wordt alleen aangeroepen als er iets klaarstaat, dus een stille minuut kost niets.
-- Opnieuw draaien begint schoon: eerst gaat de bestaande job eruit.

create extension if not exists pg_net;

select cron.unschedule(jobname) from cron.job where jobname = 'send-reminders';

select cron.schedule(
  'send-reminders',
  '* * * * *',
  $job$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'fitling_project_url')
           || '/functions/v1/send-reminders',
    headers := jsonb_build_object(
      'Authorization',
      'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'fitling_secret_key')
    ),
    timeout_milliseconds := 60000
  )
  where exists (
    select 1 from public.push_reminders
    where fire_at <= now() and (claimed_until is null or claimed_until < now())
  )
  $job$
);

-- Haalt elke nacht de aanbiedingen op: één aanroep van sync-offers per keten en deel, drie minuten uit elkaar
-- vanaf 01:00 UTC (UNFORGET S20). Een deel is 20 pagina's, 2.000 acties, zodat elke aanroep binnen de CPU-limiet
-- van een Edge Function blijft: 2 seconden, en Albert Heijn in één keer gebruikte er 2,08 (2026-11-20).
-- Grote ketens krijgen meer delen, met ruimte om te groeien. Aantallen op 2026-11-20: Albert Heijn 5.557,
-- Jumbo 1.788, PLUS 1.653, de andere ketens hoogstens 746. Antwoordt het laatste deel van een keten met
-- "more": true, geef die keten dan een deel extra.
--
-- Eenmalig per project, in de SQL Editor, nadat sync-offers is gedeployd. Vooraf in Vault twee
-- geheimen aanmaken (Integrations > Vault):
--   fitling_project_url  de project-URL, bijvoorbeeld https://<ref>.supabase.co
--   fitling_secret_key   de geheime sleutel (Settings > API Keys > Secret keys)
-- Opnieuw draaien begint schoon: eerst gaan alle bestaande jobs van deze ronde eruit.

create extension if not exists pg_net;

select cron.unschedule(jobname) from cron.job where jobname like 'sync-offers-%';

do $$
declare
  chains text[] := array[
    'albert_heijn', 'jumbo', 'lidl', 'aldi', 'plus', 'dirk', 'vomar', 'hoogvliet', 'dekamarkt', 'poiesz',
    'coop', 'gewoon_coop', 'spar', 'ekoplaza', 'nettorama', 'boni', 'mcd', 'boons_markt', 'dagwinkel',
    'amazing_oriental'
  ];
  chain text;
  parts integer;
  slot integer := 0;
begin
  foreach chain in array chains loop
    parts := case chain when 'albert_heijn' then 4 when 'jumbo' then 2 when 'plus' then 2 else 1 end;
    for part in 1 .. parts loop
      perform cron.schedule(
        format('sync-offers-%s-%s', chain, part),
        format('%s %s * * *', (slot * 3) % 60, 1 + slot * 3 / 60),
        format(
          $job$
          select net.http_post(
            url := (select decrypted_secret from vault.decrypted_secrets where name = 'fitling_project_url')
                   || '/functions/v1/sync-offers?retailer=%s&part=%s',
            headers := jsonb_build_object(
              'Authorization',
              'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'fitling_secret_key')
            ),
            timeout_milliseconds := 300000
          )
          $job$,
          chain,
          part
        )
      );
      slot := slot + 1;
    end loop;
  end loop;
end;
$$;

-- Haalt elke nacht de aanbiedingen op: één aanroep van sync-offers per keten, drie minuten uit elkaar
-- vanaf 01:00 UTC, zodat elke aanroep binnen de tijdslimiet van een Edge Function blijft (UNFORGET S20).
--
-- Eenmalig per project, in de SQL Editor, nadat sync-offers is gedeployd. Vooraf in Vault twee
-- geheimen aanmaken (Integrations > Vault):
--   fitling_project_url  de project-URL, bijvoorbeeld https://<ref>.supabase.co
--   fitling_secret_key   de geheime sleutel (Settings > API Keys > Secret keys)
-- Opnieuw draaien vervangt de bestaande jobs (cron.schedule werkt op de naam).

create extension if not exists pg_net;

do $$
declare
  chains text[] := array[
    'albert_heijn', 'jumbo', 'lidl', 'aldi', 'plus', 'dirk', 'vomar', 'hoogvliet', 'dekamarkt', 'poiesz',
    'coop', 'gewoon_coop', 'spar', 'ekoplaza', 'nettorama', 'boni', 'mcd', 'boons_markt', 'dagwinkel',
    'amazing_oriental'
  ];
  minute integer;
begin
  for i in 1 .. array_length(chains, 1) loop
    minute := (i - 1) * 3;
    perform cron.schedule(
      'sync-offers-' || chains[i],
      format('%s %s * * *', minute % 60, 1 + minute / 60),
      format(
        $job$
        select net.http_post(
          url := (select decrypted_secret from vault.decrypted_secrets where name = 'fitling_project_url')
                 || '/functions/v1/sync-offers?retailer=%s',
          headers := jsonb_build_object(
            'Authorization',
            'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'fitling_secret_key')
          ),
          timeout_milliseconds := 300000
        )
        $job$,
        chains[i]
      )
    );
  end loop;
end;
$$;

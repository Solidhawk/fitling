-- Fitling: Web Push (web fase 7), de herinneringen van de partner voor de webversie op het beginscherm.
--
-- Los van schema.sql, zodat dit op een project dat al draait kan, zonder iets anders aan te raken: in de
-- SQL Editor van Supabase plakken en uitvoeren (docs/web-push.md). Opnieuw uitvoeren kan; wat er is, blijft.
-- CI zet het bovenop schema.sql en test het in tests/push_test.sql.
--
-- Een browser abonneert zich bij zijn pushdienst en zet hier het adres en de sleutels neer; de browser plant
-- met de regels van de app (ReminderPlanner) de berichten van vandaag en morgen. De Edge Function
-- send-reminders verstuurt wat aan de beurt is. Geen sync en geen deleted_at: een rij die weg is, is weg.

create table if not exists public.push_subscriptions (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users (id) on delete cascade,
  -- Het adres bij de pushdienst. Wie het kent, kan berichten naar die browser laten sturen: alleen de eigenaar
  -- leest het.
  endpoint   text not null unique check (endpoint like 'https://%' and length(endpoint) <= 1024),
  -- De publieke sleutel van de browser (65 bytes) en het gedeelde geheim (16 bytes), base64url (RFC 8291).
  p256dh     text not null check (p256dh ~ '^[A-Za-z0-9_-]{86,88}={0,2}$'),
  auth       text not null check (auth ~ '^[A-Za-z0-9_-]{21,24}={0,2}$'),
  created_at timestamptz not null default now()
);

create table if not exists public.push_reminders (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users (id) on delete cascade,
  subscription_id uuid not null references public.push_subscriptions (id) on delete cascade,
  fire_at         timestamptz not null,
  -- De naam van de partner en wat die zegt, al in de taal van de gebruiker.
  title           text not null check (length(title) between 1 and 100),
  body            text not null check (length(body) between 1 and 400),
  -- Tot wanneer send-reminders hem aan het versturen is (claim_push_reminders).
  claimed_until   timestamptz
);
-- Voor een project waar dit bestand al eerder liep.
alter table public.push_reminders add column if not exists claimed_until timestamptz;

create index if not exists push_reminders_fire_at on public.push_reminders (fire_at);
create index if not exists push_reminders_subscription on public.push_reminders (subscription_id);
create index if not exists push_subscriptions_user on public.push_subscriptions (user_id);

alter table public.push_subscriptions enable row level security;
alter table public.push_reminders enable row level security;

-- Lezen en weghalen van eigen rijen; schrijven alleen via de twee functies hieronder, die de grenzen bewaken.
drop policy if exists "push_subscriptions: eigen rijen lezen" on public.push_subscriptions;
create policy "push_subscriptions: eigen rijen lezen" on public.push_subscriptions
  for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists "push_subscriptions: eigen rijen verwijderen" on public.push_subscriptions;
create policy "push_subscriptions: eigen rijen verwijderen" on public.push_subscriptions
  for delete to authenticated using ((select auth.uid()) = user_id);
drop policy if exists "push_reminders: eigen rijen lezen" on public.push_reminders;
create policy "push_reminders: eigen rijen lezen" on public.push_reminders
  for select to authenticated using ((select auth.uid()) = user_id);

-- Het abonnement van deze browser voor wie er nu ingelogd is. Logde eerder een ander in op dezelfde browser, dan
-- gaat diens abonnement (met de herinneringen) eraf. Hoogstens vijf browsers per gebruiker: die het langst niet
-- gebruikt is, gaat (created_at is het laatste gebruik).
create or replace function public.save_push_subscription(p_endpoint text, p_p256dh text, p_auth text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  saved uuid;
begin
  if me is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;
  if p_endpoint is null or p_endpoint not like 'https://%' then
    raise exception 'a push endpoint is an https address' using errcode = '22023';
  end if;
  delete from public.push_subscriptions where endpoint = p_endpoint and user_id <> me;
  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, created_at)
  values (me, p_endpoint, p_p256dh, p_auth, clock_timestamp())
  on conflict (endpoint) do update set p256dh = excluded.p256dh, auth = excluded.auth, created_at = excluded.created_at
  returning id into saved;
  delete from public.push_subscriptions
  where id in (select id from public.push_subscriptions where user_id = me order by created_at desc, id offset 5);
  return saved;
end;
$$;

-- Vervangt de herinneringen van een eigen abonnement: hoogstens vier (twee per dag, vandaag en morgen), en geen
-- enkele verder dan drie dagen vooruit.
create or replace function public.replace_push_reminders(p_subscription uuid, p_reminders jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
begin
  if me is null or not exists (select 1 from public.push_subscriptions where id = p_subscription and user_id = me) then
    raise exception 'not your subscription' using errcode = '42501';
  end if;
  if jsonb_typeof(p_reminders) is distinct from 'array' or jsonb_array_length(p_reminders) > 4 then
    raise exception 'at most four reminders' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_reminders) r
    where (r ->> 'fire_at')::timestamptz > now() + interval '3 days'
  ) then
    raise exception 'a reminder is at most three days ahead' using errcode = '22023';
  end if;
  delete from public.push_reminders where subscription_id = p_subscription;
  insert into public.push_reminders (user_id, subscription_id, fire_at, title, body)
  select me, p_subscription, (r ->> 'fire_at')::timestamptz, r ->> 'title', r ->> 'body'
  from jsonb_array_elements(p_reminders) r;
end;
$$;

-- Voor send-reminders: claimt wat aan de beurt is. Een aanroep die nog bezig is met een trage pushdienst en de aanroep
-- van de minuut erna sturen een herinnering zo niet allebei. Verstuurd of opgegeven gaat de rij weg; wat moet wachten
-- (een drukke pushdienst) geeft de functie meteen vrij. Een claim verloopt na vijf minuten, zodat een aanroep die
-- halverwege stopte niets voorgoed vasthoudt. `claimed_until` komt mee terug: wie vrijgeeft, geeft alleen zijn eigen
-- claim vrij. De keuze staat apart (materialized), zodat er nooit meer dan p_limit rijen geclaimd worden.
drop function if exists public.claim_push_reminders(integer);
create function public.claim_push_reminders(p_limit integer)
returns table (
  id uuid, subscription_id uuid, fire_at timestamptz, title text, body text, endpoint text, p256dh text, auth text,
  claimed_until timestamptz
)
language sql
security definer
set search_path = ''
as $$
  with due as materialized (
    select d.id from public.push_reminders d
    where d.fire_at <= now() and (d.claimed_until is null or d.claimed_until < now())
    order by d.fire_at
    limit p_limit
    for update skip locked
  ), claimed as (
    update public.push_reminders r
    set claimed_until = now() + interval '5 minutes'
    from due
    where r.id = due.id
    returning r.id, r.subscription_id, r.fire_at, r.title, r.body, r.claimed_until
  )
  select c.id, c.subscription_id, c.fire_at, c.title, c.body, s.endpoint, s.p256dh, s.auth, c.claimed_until
  from claimed c
  join public.push_subscriptions s on s.id = c.subscription_id
  order by c.fire_at;
$$;

revoke all on function public.save_push_subscription(text, text, text) from public, anon;
revoke all on function public.replace_push_reminders(uuid, jsonb) from public, anon;
grant execute on function public.save_push_subscription(text, text, text) to authenticated;
grant execute on function public.replace_push_reminders(uuid, jsonb) to authenticated;
revoke all on function public.claim_push_reminders(integer) from public, anon, authenticated;
grant execute on function public.claim_push_reminders(integer) to service_role;

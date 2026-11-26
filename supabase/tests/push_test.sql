-- Web Push (web fase 7): wie een abonnement en de geplande herinneringen mag zien en zetten (web-push.sql).
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- P en Q zijn twee gebruikers; P zet Fitling op het beginscherm van zijn telefoon.
insert into auth.users (id, email) values
  ('70000000-0000-0000-0000-000000000001', 'p@example.test'),
  ('70000000-0000-0000-0000-000000000002', 'q@example.test');

create temporary table ids (name text primary key, id uuid);
grant all on ids to authenticated;

set local role authenticated;
set local request.jwt.claims = '{"sub": "70000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select lives_ok($$
  insert into ids select 'p', public.save_push_subscription(
    'https://web.push.apple.com/QGuQyavXutnMnZwwvJzzhVjVr4pjXwmOhM0mCc5E', repeat('B', 87), repeat('a', 22))
$$, 'een gebruiker zet het abonnement van zijn browser');

select is(
  (select count(*)::int from public.push_subscriptions), 1, 'en ziet het');

select lives_ok($$
  select public.replace_push_reminders((select id from ids where name = 'p'), jsonb_build_array(
    jsonb_build_object('fire_at', now() + interval '1 hour', 'title', 'Pip', 'body', 'Nog niets gegeten vandaag?'),
    jsonb_build_object('fire_at', now() + interval '7 hours', 'title', 'Pip', 'body', 'Hoe ging het vandaag?')))
$$, 'en zet de herinneringen voor vandaag en morgen');

select is((select count(*)::int from public.push_reminders), 2, 'die hij ziet');

select lives_ok($$
  select public.replace_push_reminders((select id from ids where name = 'p'), jsonb_build_array(
    jsonb_build_object('fire_at', now() + interval '2 hours', 'title', 'Pip', 'body', 'Tijd voor lunch')))
$$, 'een nieuw plan');
select is((select count(*)::int from public.push_reminders), 1, 'vervangt het oude');

select throws_ok($$
  select public.replace_push_reminders((select id from ids where name = 'p'), (
    select jsonb_agg(jsonb_build_object('fire_at', now() + make_interval(hours => n), 'title', 'Pip', 'body', 'Hoi'))
    from generate_series(1, 5) n))
$$, '22023', null, 'hoogstens vier: twee per dag, vandaag en morgen');

select throws_ok($$
  select public.replace_push_reminders((select id from ids where name = 'p'), jsonb_build_array(
    jsonb_build_object('fire_at', now() + interval '4 days', 'title', 'Pip', 'body', 'Later')))
$$, '22023', null, 'niet verder vooruit dan overmorgen');

select throws_ok($$
  insert into public.push_reminders (user_id, subscription_id, fire_at, title, body)
  values ('70000000-0000-0000-0000-000000000001', (select id from ids where name = 'p'), now(), 'Pip', 'Hoi')
$$, '42501', null, 'zelf rijen schrijven gaat niet: alleen via replace_push_reminders');

select throws_ok($$
  select public.save_push_subscription('http://example.test/intern', repeat('B', 87), repeat('a', 22))
$$, '22023', null, 'een abonnement is een https-adres');

-- Q ziet en raakt niets van P.
set local request.jwt.claims = '{"sub": "70000000-0000-0000-0000-000000000002", "role": "authenticated"}';

select is_empty($$ select id from public.push_subscriptions $$, 'een ander ziet het abonnement niet');
select is_empty($$ select id from public.push_reminders $$, 'en de herinneringen niet');

select throws_ok($$
  select public.replace_push_reminders((select id from ids where name = 'p'), jsonb_build_array(
    jsonb_build_object('fire_at', now() + interval '1 hour', 'title', 'Pip', 'body', 'Hoi')))
$$, '42501', null, 'en kan er geen herinneringen op zetten');

select lives_ok($$ delete from public.push_subscriptions $$, 'verwijderen raakt alleen eigen rijen');

-- Q logt in op dezelfde browser: het abonnement hoort nu bij Q, met de herinneringen van P eraf.
select lives_ok($$
  insert into ids select 'q', public.save_push_subscription(
    'https://web.push.apple.com/QGuQyavXutnMnZwwvJzzhVjVr4pjXwmOhM0mCc5E', repeat('C', 87), repeat('b', 22))
$$, 'dezelfde browser met een andere gebruiker');
select is((select count(*)::int from public.push_subscriptions), 1, 'is van die gebruiker');

reset role;
select is(
  (select count(*)::int from public.push_subscriptions where user_id = '70000000-0000-0000-0000-000000000001'), 0,
  'en niet meer van de vorige');
select is((select count(*)::int from public.push_reminders), 0, 'zonder diens herinneringen');

-- Uitloggen: de eigen browser eraf.
set local role authenticated;
set local request.jwt.claims = '{"sub": "70000000-0000-0000-0000-000000000002", "role": "authenticated"}';
select lives_ok($$ delete from public.push_subscriptions where id = (select id from ids where name = 'q') $$, 'uitloggen haalt het abonnement weg');
reset role;
select is((select count(*)::int from public.push_subscriptions), 0, 'en dat is weg');

-- Hoogstens vijf browsers: de browser die het langst niet gebruikt is, gaat; opnieuw opslaan telt als gebruik.
set local request.jwt.claims = '{"sub": "70000000-0000-0000-0000-000000000002", "role": "authenticated"}';
set local role authenticated;
select lives_ok($$
  select public.save_push_subscription('https://fcm.googleapis.com/fcm/send/b' || n, repeat('B', 87), repeat('a', 22))
  from generate_series(1, 5) n
$$, 'vijf browsers');
select lives_ok($$ select public.save_push_subscription('https://fcm.googleapis.com/fcm/send/b1', repeat('B', 87), repeat('a', 22)) $$,
  'de eerste weer gebruikt');
select lives_ok($$ select public.save_push_subscription('https://fcm.googleapis.com/fcm/send/b6', repeat('B', 87), repeat('a', 22)) $$,
  'een zesde');
select is(
  (select array_agg(endpoint order by endpoint) from public.push_subscriptions),
  array['https://fcm.googleapis.com/fcm/send/b1', 'https://fcm.googleapis.com/fcm/send/b3', 'https://fcm.googleapis.com/fcm/send/b4',
        'https://fcm.googleapis.com/fcm/send/b5', 'https://fcm.googleapis.com/fcm/send/b6'],
  'de tweede ging, niet de eerste die net nog gebruikt werd');
reset role;

set local role anon;
select throws_ok($$
  select public.save_push_subscription('https://web.push.apple.com/x', repeat('B', 87), repeat('a', 22))
$$, '42501', null, 'zonder account geen abonnement');

reset role;

-- Versturen (send-reminders): wat aan de beurt is, wordt eerst geclaimd. Een aanroep die nog bezig is met een trage
-- pushdienst en de aanroep van de minuut erna sturen een herinnering zo niet allebei.
insert into public.push_subscriptions (id, user_id, endpoint, p256dh, auth) values
  ('71000000-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000002', 'https://web.push.apple.com/claim',
   repeat('B', 87), repeat('a', 22));
insert into public.push_reminders (id, user_id, subscription_id, fire_at, title, body) values
  ('72000000-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000002', '71000000-0000-0000-0000-000000000001',
   now() - interval '1 minute', 'Pip', 'Tijd voor lunch'),
  ('72000000-0000-0000-0000-000000000002', '70000000-0000-0000-0000-000000000002', '71000000-0000-0000-0000-000000000001',
   now() + interval '1 hour', 'Pip', 'Hoe ging het vandaag?');

set local role service_role;
select is(
  (select array_agg(id::text || ' ' || endpoint || ' ' || (claimed_until = now() + interval '5 minutes'))
   from public.claim_push_reminders(10)),
  array['72000000-0000-0000-0000-000000000001 https://web.push.apple.com/claim true'],
  'wat aan de beurt is, wordt vijf minuten geclaimd, met het adres van de browser; wat later komt niet');
select is_empty($$ select id from public.claim_push_reminders(10) $$, 'een tweede aanroep krijgt het niet nog eens');
update public.push_reminders set claimed_until = null where id = '72000000-0000-0000-0000-000000000001';
select is(
  (select count(*)::int from public.claim_push_reminders(10)), 1, 'vrijgegeven (een drukke pushdienst) komt het terug');
update public.push_reminders set claimed_until = now() - interval '1 second'
where id = '72000000-0000-0000-0000-000000000001';
select is(
  (select count(*)::int from public.claim_push_reminders(10)), 1,
  'een claim die verliep (een aanroep die halverwege stopte) houdt het niet vast');
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub": "70000000-0000-0000-0000-000000000002", "role": "authenticated"}';
select throws_ok($$ select id from public.claim_push_reminders(10) $$, '42501', null, 'alleen send-reminders claimt');
reset role;
set local role anon;
select throws_ok($$ select id from public.claim_push_reminders(10) $$, '42501', null, 'ook zonder account niet');
reset role;

select * from finish();
rollback;

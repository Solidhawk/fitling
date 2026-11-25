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

set local role anon;
select throws_ok($$
  select public.save_push_subscription('https://web.push.apple.com/x', repeat('B', 87), repeat('a', 22))
$$, '42501', null, 'zonder account geen abonnement');

reset role;
select * from finish();
rollback;

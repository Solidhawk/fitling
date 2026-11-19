begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- A, B en C zijn drie gebruikers. L is de lijst van A, I het eerste item erop.
insert into auth.users (id, email) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a@example.test'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'b@example.test'),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'c@example.test');

insert into public.products (id, source, source_id, gtin, name, kcal_100, updated_at) values
  ('10000000-0000-0000-0000-000000000001', 'off', '8710400000013', '8710400000013', '{"nl": "Pindakaas"}', 600, now());
insert into public.supermarkets (id, name) values ('ah', 'Albert Heijn');
insert into public.offers (supermarket_id, external_id, title, price_cents, valid_from, valid_to) values
  ('ah', 'x1', 'Pindakaas 350 g', 199, current_date, current_date + 6);

select is_empty($$
  select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity
$$, 'elke tabel in public heeft RLS');

select throws_ok($$
  insert into public.products (source, source_id, gtin, name, updated_at)
  values ('off', 'andere-bron', '8710400000013', '{"nl": "Dubbel"}', now())
$$, '23505', null, 'dezelfde barcode kan maar één keer in de gedeelde cache staan');

select throws_ok($$
  insert into public.products (source, gtin, name, updated_at)
  values ('off', '871040000001', '{"nl": "Twaalf cijfers"}', now())
$$, '23514', null, 'een barcode die niet genormaliseerd is, wordt geweigerd');

-- ---------------------------------------------------------------------------------------------
-- Gebruiker A
-- ---------------------------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", "role": "authenticated"}';

select lives_ok($$
  insert into public.food_entries (id, user_id, consumed_on, meal, product_id, name, quantity, quantity_unit, kcal, updated_at, synced_at)
  values ('30000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '2026-11-18', 'lunch',
          '10000000-0000-0000-0000-000000000001', 'Pindakaas', 30, 'g', 180, '2026-11-18 12:00:00+00', '2000-01-01 00:00:00+00')
$$, 'A kan een eigen voedingslog aanmaken');

select is(
  (select synced_at from public.food_entries where id = '30000000-0000-0000-0000-000000000001'),
  now(),
  'de server zet synced_at, ook als de client een waarde meestuurt'
);

select throws_ok($$
  insert into public.food_entries (user_id, consumed_on, meal, name, quantity, quantity_unit, kcal, updated_at)
  values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '2026-11-18', 'lunch', 'Van een ander', 30, 'g', 180, now())
$$, '42501', null, 'A kan geen voedingslog voor B aanmaken');

select is_empty($$
  update public.food_entries set kcal = 999, updated_at = '2026-11-18 11:00:00+00'
  where id = '30000000-0000-0000-0000-000000000001' returning id
$$, 'een update met een oudere updated_at wordt genegeerd');

select is_empty($$
  delete from public.food_entries returning id
$$, 'een rij echt verwijderen kan niet; verwijderen is deleted_at zetten');

select lives_ok($$
  insert into public.water_entries (id, user_id, consumed_on, amount_ml, updated_at)
  values ('50000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '2026-11-18', 250, now() + interval '1 year')
$$, 'een rij met een klok die een jaar voorloopt, wordt aangenomen');
select is(
  (select updated_at from public.water_entries where id = '50000000-0000-0000-0000-000000000001'),
  now(),
  'maar updated_at wordt teruggezet naar de tijd van de server'
);

select lives_ok($$
  update public.food_entries set deleted_at = now(), updated_at = '2026-11-18 13:00:00+00', synced_at = '2000-01-01 00:00:00+00'
  where id = '30000000-0000-0000-0000-000000000001'
$$, 'A kan een eigen rij als verwijderd markeren');
select is(
  (select synced_at from public.food_entries where id = '30000000-0000-0000-0000-000000000001'),
  now(),
  'ook bij een update zet de server synced_at'
);

select is((select count(*) from public.products), 1::bigint, 'A ziet het gedeelde product');

select throws_ok($$
  insert into public.products (source, name, updated_at) values ('off', '{"nl": "Nep"}', now())
$$, '42501', null, 'A kan geen gedeeld product aanmaken');

select lives_ok($$
  insert into public.products (id, owner_id, source, name, kcal_100, updated_at)
  values ('10000000-0000-0000-0000-00000000000a', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'user', '{"nl": "Oma''s soep"}', 45, now())
$$, 'A kan een eigen product aanmaken');

select is_empty($$
  update public.products set kcal_100 = 1, updated_at = now() + interval '1 hour'
  where id = '10000000-0000-0000-0000-000000000001' returning id
$$, 'A kan een gedeeld product niet wijzigen');

select is((select count(*) from public.offers), 1::bigint, 'A leest de aanbiedingen');

select throws_ok($$
  insert into public.offers (supermarket_id, external_id, title, price_cents, valid_from, valid_to)
  values ('ah', 'x2', 'Nep', 1, current_date, current_date)
$$, '42501', null, 'A kan geen aanbieding aanmaken');

select lives_ok($$
  insert into public.shopping_lists (id, name, created_by, updated_at)
  values ('20000000-0000-0000-0000-000000000001', 'Thuis', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', now())
$$, 'A kan een lijst aanmaken');

select lives_ok($$
  insert into public.shopping_list_members (list_id, user_id, role, display_name)
  values ('20000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'owner', 'Anne')
$$, 'de maker wordt eigenaar van de eigen lijst');

select lives_ok($$
  insert into public.shopping_items (id, list_id, name, updated_by, updated_at)
  values ('40000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Melk',
          'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', now())
$$, 'A kan een item op de eigen lijst zetten');

select lives_ok($$
  select set_config('test.invite', public.create_shopping_list_invite('20000000-0000-0000-0000-000000000001'), true)
$$, 'een lid kan een uitnodiging maken');

select matches(current_setting('test.invite'), '^[0-9A-F]{12}$', 'de uitnodigingscode is twaalf tekens');

-- ---------------------------------------------------------------------------------------------
-- Gebruiker C: geen lid
-- ---------------------------------------------------------------------------------------------
set local request.jwt.claims = '{"sub": "cccccccc-cccc-cccc-cccc-cccccccccccc", "role": "authenticated"}';

select throws_ok($$
  select public.create_shopping_list_invite('20000000-0000-0000-0000-000000000001')
$$, '42501', null, 'wie geen lid is, kan geen uitnodiging maken');

-- ---------------------------------------------------------------------------------------------
-- Gebruiker B
-- ---------------------------------------------------------------------------------------------
set local request.jwt.claims = '{"sub": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", "role": "authenticated"}';

select is_empty('select id from public.shopping_lists', 'B ziet de lijst van A niet');
select is_empty('select id from public.shopping_items', 'B ziet de items van A niet');
select is_empty('select id from public.food_entries', 'B ziet de voedingslogs van A niet');
select is((select count(*) from public.products), 1::bigint, 'B ziet het eigen product van A niet');

select throws_ok($$
  insert into public.shopping_items (list_id, name, updated_by, updated_at)
  values ('20000000-0000-0000-0000-000000000001', 'Stiekem', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', now())
$$, '42501', null, 'B kan niets op de lijst van A zetten');

select throws_ok($$
  insert into public.shopping_list_members (list_id, user_id, role, display_name)
  values ('20000000-0000-0000-0000-000000000001', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'member', 'Bo')
$$, '42501', null, 'B kan zichzelf niet zonder uitnodiging toevoegen');

select throws_ok($$
  select public.join_shopping_list('000000000000', 'Bo')
$$, 'P0002', null, 'een onjuiste code geeft geen toegang');

select is(
  public.join_shopping_list(lower(current_setting('test.invite')), 'Bo'),
  '20000000-0000-0000-0000-000000000001'::uuid,
  'met de code wordt B lid, ook als de code in kleine letters is getypt'
);

select is((select count(*) from public.shopping_items), 1::bigint, 'B ziet nu het item');

select lives_ok($$
  update public.shopping_items
  set is_checked = true, updated_by = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', updated_at = now()
  where id = '40000000-0000-0000-0000-000000000001'
$$, 'B kan een item afvinken');

select is(
  (select count(*) from public.shopping_list_members where list_id = '20000000-0000-0000-0000-000000000001'),
  2::bigint,
  'B ziet beide leden'
);

-- ---------------------------------------------------------------------------------------------
-- De eigenaar gaat weg, daarna het laatste lid
-- ---------------------------------------------------------------------------------------------
set local request.jwt.claims = '{"sub": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", "role": "authenticated"}';

select lives_ok($$
  delete from public.shopping_list_members
  where list_id = '20000000-0000-0000-0000-000000000001' and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
$$, 'A kan de lijst verlaten');

select is_empty('select id from public.shopping_lists', 'A ziet de lijst daarna niet meer');

select throws_ok($$
  insert into public.shopping_list_members (list_id, user_id, role, display_name)
  values ('20000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'owner', 'Anne')
$$, '42501', null, 'A kan zichzelf niet terugzetten als eigenaar');

set local request.jwt.claims = '{"sub": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", "role": "authenticated"}';

select is(
  (select role from public.shopping_list_members where user_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
  'owner',
  'het langst aanwezige lid wordt eigenaar'
);

select lives_ok($$
  delete from public.shopping_list_members where user_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
$$, 'B kan de lijst verlaten');

reset role;
select is_empty($$
  select id from public.shopping_lists where id = '20000000-0000-0000-0000-000000000001'
$$, 'een lijst zonder leden verdwijnt');
select is_empty('select id from public.shopping_items', 'de items verdwijnen mee');

-- ---------------------------------------------------------------------------------------------
-- Account verwijderen
-- ---------------------------------------------------------------------------------------------
select lives_ok($$
  delete from auth.users where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
$$, 'een account kan verwijderd worden');
select is((select count(*) from public.food_entries), 0::bigint, 'de voedingslogs van het account zijn weg');
select is((select count(*) from public.products), 1::bigint, 'het eigen product is weg, het gedeelde product blijft');

-- ---------------------------------------------------------------------------------------------
-- Niet ingelogd
-- ---------------------------------------------------------------------------------------------
set local role anon;
set local request.jwt.claims = '{"role": "anon"}';
select is_empty('select id from public.products', 'anon ziet geen producten');
select is_empty('select id from public.offers', 'anon ziet geen aanbiedingen');
select throws_ok($$
  select public.join_shopping_list('000000000000', 'X')
$$, '42501', null, 'anon kan geen lijst joinen');

select * from finish();
rollback;

begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

insert into auth.users (id, email) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a@example.test');

-- ---------------------------------------------------------------------------------------------
-- Teller per gebruiker per uur (lookup-product, submit-product)
-- ---------------------------------------------------------------------------------------------
select is(public.consume_rate_limit('lookup:test', 2), true, 'de eerste aanroep valt binnen de grens');
select is(public.consume_rate_limit('lookup:test', 2), true, 'de tweede aanroep valt binnen de grens');
select is(public.consume_rate_limit('lookup:test', 2), false, 'de derde aanroep is er een te veel');
select is(public.consume_rate_limit('lookup:other', 2), true, 'een andere gebruiker heeft een eigen teller');
select is(
  (select window_start from private.rate_limits where bucket = 'lookup:test'),
  date_trunc('hour', now()),
  'het venster begint op het hele uur'
);

-- ---------------------------------------------------------------------------------------------
-- Eén gedeelde rij per barcode
-- ---------------------------------------------------------------------------------------------
create temporary table stored (round integer, id uuid, kcal numeric) on commit drop;

insert into stored
select 1, p.id, p.kcal_100 from public.store_shared_product('{
  "source": "off", "source_id": "8712100849084", "gtin": "8712100849084",
  "name": {"de": "Double Caramel"}, "brand": "Magnum, Unilever", "search_name": "double caramel magnum, unilever",
  "quantity_unit": "ml", "serving_size": 88, "kcal_100": 338, "protein_100": 3.2, "carbs_100": 36,
  "sugars_100": 33, "fat_100": 20, "saturated_fat_100": 14, "fiber_100": null, "salt_100": 0.17,
  "image_url": null, "is_verified": true, "fetched_at": "2026-11-19T12:00:00Z"
}'::jsonb) as p;

-- Een eigen product van een gebruiker met dezelfde barcode blijft er los van.
insert into public.products (owner_id, source, gtin, name, kcal_100, updated_at)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'user', '8712100849084', '{"nl": "Mijn ijsje"}', 300, now());

insert into stored
select 2, p.id, p.kcal_100 from public.store_shared_product('{
  "source": "off", "source_id": "8712100849084", "gtin": "8712100849084",
  "name": {"de": "Double Caramel"}, "brand": "Magnum, Unilever", "search_name": "double caramel magnum, unilever",
  "quantity_unit": "ml", "serving_size": 88, "kcal_100": 340, "protein_100": 3.2, "carbs_100": 36,
  "sugars_100": 33, "fat_100": 20, "saturated_fat_100": 14, "fiber_100": null, "salt_100": 0.17,
  "image_url": null, "is_verified": true, "fetched_at": "2026-12-20T12:00:00Z"
}'::jsonb) as p;

select is(
  (select count(*) from public.products where gtin = '8712100849084' and owner_id is null),
  1::bigint,
  'twee keer opslaan geeft één gedeelde rij'
);
select is((select count(distinct id) from stored), 1::bigint, 'de tweede keer houdt de rij haar id');
select is((select kcal from stored where round = 2), 340.0::numeric, 'de tweede keer werkt de waarden bij');
select is(
  (select fetched_at from public.products where gtin = '8712100849084' and owner_id is null),
  '2026-12-20T12:00:00Z'::timestamptz,
  'het moment van ophalen wordt bijgewerkt'
);
select is(
  (select kcal_100 from public.products where gtin = '8712100849084' and owner_id is not null),
  300.0::numeric,
  'het eigen product van de gebruiker blijft ongewijzigd'
);

-- ---------------------------------------------------------------------------------------------
-- Alleen Edge Functions (service_role) mogen deze functies aanroepen
-- ---------------------------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", "role": "authenticated"}';
select throws_ok($$
  select public.consume_rate_limit('lookup:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 1000000)
$$, '42501', null, 'een gebruiker kan de teller niet zelf ophogen of omzeilen');
select throws_ok($$
  select public.store_shared_product('{}'::jsonb)
$$, '42501', null, 'een gebruiker kan geen gedeeld product schrijven');
reset role;

set local role anon;
select throws_ok($$
  select public.consume_rate_limit('lookup:x', 1)
$$, '42501', null, 'anon kan de teller niet aanroepen');
reset role;

select * from finish();
rollback;

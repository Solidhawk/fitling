-- Een product delen (TASKS 2.8): wat submit_shared_product met de gedeelde rij en de inzending doet (submit-product.sql).
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- A deelt als eerste, B daarna voor dezelfde barcode.
insert into auth.users (id, email) values
  ('80000000-0000-0000-0000-000000000001', 'a@example.test'),
  ('80000000-0000-0000-0000-000000000002', 'b@example.test');

create temporary table koek as select jsonb_build_object(
  'gtin', '8712100849084', 'name', jsonb_build_object('nl', 'Koek'), 'brand', 'Bakker', 'search_name', 'koek bakker',
  'quantity_unit', 'g', 'serving_size', 30, 'kcal_100', 400, 'protein_100', 6, 'carbs_100', 60, 'fat_100', 15
) as product;

select is(
  (select made_new from public.submit_shared_product('80000000-0000-0000-0000-000000000001', '{"name": "Koek"}',
    (select product from koek))),
  true, 'de eerste inzending voor een barcode wordt de gedeelde rij');
select is(
  (select source || ' ' || is_verified || ' ' || (owner_id is null) || ' ' || kcal_100 from public.products
   where gtin = '8712100849084'),
  'user false true 400.0', 'van een gebruiker, voor iedereen, nooit geverifieerd');
select is(
  (select status || ' ' || (product_id is not null) || ' ' || (payload ->> 'name') from public.product_submissions
   where user_id = '80000000-0000-0000-0000-000000000001'),
  'accepted true Koek', 'de inzending is bewaard zoals hij kwam, en aangenomen');

select is(
  (select made_new from public.submit_shared_product('80000000-0000-0000-0000-000000000002', '{"name": "Rommel"}',
    (select product || jsonb_build_object('name', jsonb_build_object('nl', 'Rommel')) from koek))),
  false, 'een tweede inzender maakt geen rij');
select is(
  (select name ->> 'nl' from public.products where gtin = '8712100849084'), 'Koek', 'en verandert de rij niet');
select is(
  (select status from public.product_submissions where user_id = '80000000-0000-0000-0000-000000000002'), 'pending',
  'zijn inzending wacht');

select public.submit_shared_product('80000000-0000-0000-0000-000000000001', '{"name": "Speculaas"}',
  (select product || jsonb_build_object('name', jsonb_build_object('nl', 'Speculaas'), 'kcal_100', 450) from koek));
select is(
  (select (name ->> 'nl') || ' ' || kcal_100 from public.products where gtin = '8712100849084'), 'Speculaas 450.0',
  'wie de rij maakte, mag hem verbeteren');

update public.products set deleted_at = now(), updated_at = now() + interval '2 minutes' where gtin = '8712100849084';
select public.submit_shared_product('80000000-0000-0000-0000-000000000002', '{"name": "Kaneelkoek"}',
  (select product || jsonb_build_object('name', jsonb_build_object('nl', 'Kaneelkoek')) from koek));
select is(
  (select (name ->> 'nl') || ' ' || (deleted_at is null) from public.products where gtin = '8712100849084'),
  'Kaneelkoek true', 'een weggehaalde rij komt terug met de nieuwe waarden, ook na een klok die voorliep');
select is(
  (select count(*)::int from public.products where gtin = '8712100849084'), 1, 'en het blijft één rij');

-- Een rij uit Open Food Facts verandert alleen door lookup-product.
select public.store_shared_product(jsonb_build_object(
  'source', 'off', 'source_id', '5000112548167', 'gtin', '5000112548167', 'name', jsonb_build_object('en', 'Cola'),
  'search_name', 'cola', 'quantity_unit', 'ml', 'kcal_100', 42, 'is_verified', true, 'fetched_at', now()));
select is(
  (select made_new from public.submit_shared_product('80000000-0000-0000-0000-000000000001', '{"name": "Nep"}',
    jsonb_build_object('gtin', '5000112548167', 'name', jsonb_build_object('nl', 'Nep'), 'search_name', 'nep',
      'quantity_unit', 'ml', 'kcal_100', 1))),
  false, 'een barcode uit Open Food Facts houdt zijn rij');
select is(
  (select (name ->> 'en') || ' ' || kcal_100 || ' ' || source from public.products where gtin = '5000112548167'),
  'Cola 42.0 off', 'ongewijzigd');

set local role authenticated;
set local request.jwt.claims = '{"sub": "80000000-0000-0000-0000-000000000001", "role": "authenticated"}';
select throws_ok(
  $$ select public.submit_shared_product('80000000-0000-0000-0000-000000000001', '{}', '{}') $$,
  '42501', null, 'alleen submit-product deelt');
reset role;
set local role anon;
select throws_ok(
  $$ select public.submit_shared_product('80000000-0000-0000-0000-000000000001', '{}', '{}') $$,
  '42501', null, 'ook zonder account niet');
reset role;

select * from finish();
rollback;

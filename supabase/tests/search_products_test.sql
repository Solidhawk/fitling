-- Searching the shared products (supabase/search-products.sql): every word in any order, the best match first, in the
-- same order as FoodLog.bestMatches. The made-up words keep other tests' products out of the results.
begin;
select plan(6);

insert into public.products (id, source, source_id, name, search_name, is_verified, updated_at, deleted_at) values
  ('7a1b0000-0000-4000-8000-000000000001', 'nevo', 'search-test-1', '{"nl": "Kazorbelen rauw"}', 'kazorbelen rauw', true, now(), null),
  ('7a1b0000-0000-4000-8000-000000000002', 'nevo', 'search-test-2', '{"nl": "Taart zorbel- v deeg"}', 'taart zorbel- v deeg', true, now(), null),
  ('7a1b0000-0000-4000-8000-000000000003', 'nevo', 'search-test-3', '{"nl": "Zorbelmoes blik"}', 'zorbelmoes blik', true, now(), null),
  ('7a1b0000-0000-4000-8000-000000000004', 'off', 'search-test-4', '{"nl": "Zorbel extra"}', 'zorbel extra', false, now(), null),
  ('7a1b0000-0000-4000-8000-000000000005', 'nevo', 'search-test-5', '{"nl": "Zorbel z schil gem"}', 'zorbel z schil gem', true, now(), null),
  ('7a1b0000-0000-4000-8000-000000000006', 'nevo', 'search-test-6', '{"nl": "Zorbel weg"}', 'zorbel weg', true, now(), now()),
  ('7a1b0000-0000-4000-8000-000000000007', 'nevo', 'search-test-7', '{"nl": "Kwibus halfvolle"}', 'kwibus halfvolle', true, now(), null);

select results_eq(
  $$ select search_name from public.search_products('zorbel') $$,
  $$ values ('zorbel z schil gem'), ('zorbel extra'), ('zorbelmoes blik'), ('taart zorbel- v deeg'), ('kazorbelen rauw') $$,
  'the best match first, and a removed product is not found'
);
select results_eq(
  $$ select search_name from public.search_products('halfvolle kwibus') $$,
  $$ values ('kwibus halfvolle') $$,
  'every word, in any order'
);
select is_empty($$ select * from public.search_products('kwibus halfvol zorbel') $$, 'every word must be in the name');
select is_empty($$ select * from public.search_products('   ') $$, 'an empty key finds nothing');
select is((select count(*)::int from public.search_products('zorbel', 2)), 2, 'at most max_results');
-- A word is taken literally: % and _ are no wildcards.
select is_empty($$ select * from public.search_products('zorb%') $$, 'a % is just a character');

select * from finish();
rollback;

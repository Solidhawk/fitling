-- The NEVO import (scripts/nevo-import.mjs) on the real schema. CI applies the SQL made from
-- scripts/fixtures/nevo-test.csv twice, then the SQL of the same file without its last food (9003).
begin;
select plan(8);

select is((select count(*)::int from public.products where source = 'nevo' and deleted_at is null), 2,
  'two foods remain from the smaller table');
select ok((select deleted_at is not null from public.products where source = 'nevo' and source_id = '9003'),
  'a food that is no longer in the table is retired');
select is((select kcal_100 from public.products where source = 'nevo' and source_id = '9001'), 52.0,
  'kcal as in NEVO');
select is((select salt_100 from public.products where source = 'nevo' and source_id = '9001'), 0.95,
  'salt from sodium');
select is((select quantity_unit from public.products where source = 'nevo' and source_id = '9002'), 'ml',
  'a drink is per 100 ml');
select is((select name ->> 'nl' from public.products where source = 'nevo' and source_id = '9002'), 'Testdrank O''Neill',
  'the Dutch name as in NEVO');
select is((select salt_100 from public.products where source = 'nevo' and source_id = '9003'), 97.5,
  'the highest values fit the columns');
select ok((select bool_and(is_verified and owner_id is null) from public.products where source = 'nevo'),
  'NEVO foods are shared and verified');

select * from finish();
rollback;

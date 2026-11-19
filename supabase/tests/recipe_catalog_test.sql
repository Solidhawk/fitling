-- De gedeelde recepten uit supabase/seed/recipes.sql (TASKS 5.1).
begin;
create extension if not exists pgtap with schema extensions;
select plan(4);

select is((select count(*)::int from public.recipes where owner_id is null), 24, 'de gedeelde recepten staan erin');
select is(
  (select count(*)::int from public.recipes r where owner_id is null
     and not exists (select 1 from public.recipe_ingredients i where i.recipe_id = r.id)),
  0,
  'elk recept heeft ingrediënten'
);
select is((select count(*)::int from public.recipes where owner_id is null and kcal_per_serving <= 0), 0, 'elk recept heeft energie per portie');
select is(
  (select count(*)::int from public.recipes where owner_id is null and (title ->> 'nl' is null or title ->> 'en' is null or title ->> 'de' is null)),
  0,
  'elk recept heeft een titel in nl, en en de'
);

select * from finish();
rollback;

-- De gedeelde oefeningen en kant-en-klare schema's uit supabase/seed/sport.sql (TASKS 4.1).
begin;
create extension if not exists pgtap with schema extensions;
select plan(6);

select is((select count(*)::int from public.exercises where owner_id is null), 113, 'de gedeelde oefeningen staan erin');
select is((select count(*)::int from public.programs where owner_id is null), 3, 'de drie kant-en-klare schema''s staan erin');
select is(
  (select array_agg(days_per_week order by days_per_week) from public.programs where owner_id is null),
  array[3, 4, 6],
  'Full body 3×, Upper/Lower 4× en PPL 6×'
);
select is((select count(*)::int from public.program_days where owner_id is null), 13, 'elk schema heeft een dag per trainingsdag');
select is((select count(*)::int from public.program_exercises where owner_id is null), 69, 'alle oefeningen van de schemadagen staan erin');
select is(
  (select count(*)::int from public.exercises where owner_id is null and (name ->> 'nl' is null or name ->> 'en' is null or name ->> 'de' is null)),
  0,
  'elke oefening heeft een naam in nl, en en de'
);

select * from finish();
rollback;

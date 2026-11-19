begin;
create extension if not exists pgtap with schema extensions;
select plan(19);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@example.test'),
  ('22222222-2222-2222-2222-222222222222', 'b@example.test');

select has_table('public', 'profiles', 'tabel profiles bestaat');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.profiles'::regclass),
  'RLS staat aan op profiles'
);

-- Gebruiker A
set local role authenticated;
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';

select lives_ok($$
  insert into public.profiles (
    id, health_consent_at, health_consent_version, birth_date, sex, height_cm, weight_kg,
    activity_level, goal, kcal_target, protein_target_g, carbs_target_g, fat_target_g,
    targets_are_manual, updated_at, synced_at
  ) values (
    '11111111-1111-1111-1111-111111111111', now(), 1, '1996-01-10', 'male', 180, 80,
    'moderate', 'maintain', 2760, 128, 389, 77,
    false, '2026-11-18 12:00:00+00', '2000-01-01 00:00:00+00'
  )
$$, 'A kan een eigen profiel aanmaken');

select is((select count(*) from public.profiles), 1::bigint, 'A ziet het eigen profiel');
select is(
  (select synced_at from public.profiles where id = '11111111-1111-1111-1111-111111111111'),
  now(),
  'de server zet synced_at, ook als de client een waarde meestuurt'
);

select is_empty($$
  update public.profiles set weight_kg = 70, updated_at = '2026-11-18 11:00:00+00'
  where id = '11111111-1111-1111-1111-111111111111' returning id
$$, 'een update met een oudere updated_at wordt genegeerd');
select is(
  (select weight_kg from public.profiles where id = '11111111-1111-1111-1111-111111111111'),
  80.0::numeric,
  'het gewicht is na de oudere update ongewijzigd'
);

select lives_ok($$
  update public.profiles set weight_kg = 79.5, updated_at = '2026-11-18 13:00:00+00'
  where id = '11111111-1111-1111-1111-111111111111'
$$, 'een update met een nieuwere updated_at wordt toegepast');
select is(
  (select weight_kg from public.profiles where id = '11111111-1111-1111-1111-111111111111'),
  79.5::numeric,
  'het gewicht is na de nieuwere update bijgewerkt'
);

select throws_ok($$
  update public.profiles set kcal_target = 0, updated_at = '2026-11-18 14:00:00+00'
  where id = '11111111-1111-1111-1111-111111111111'
$$, '23514', null, 'kcal_target 0 wordt geweigerd');
select lives_ok($$
  update public.profiles set kcal_target = 20000, updated_at = '2026-11-18 15:00:00+00'
  where id = '11111111-1111-1111-1111-111111111111'
$$, 'kcal_target 20000 is toegestaan');
select throws_ok($$
  update public.profiles set sex = 'x', updated_at = '2026-11-18 16:00:00+00'
  where id = '11111111-1111-1111-1111-111111111111'
$$, '23514', null, 'een onbekend geslacht wordt geweigerd');
select lives_ok($$
  update public.profiles set activity_level = 'very_active', goal = 'build_muscle', updated_at = '2026-11-18 17:00:00+00'
  where id = '11111111-1111-1111-1111-111111111111'
$$, 'de enum-waarden uit FitlingCore met een underscore zijn geldig');

-- Gebruiker B
set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';

select is((select count(*) from public.profiles), 0::bigint, 'B ziet het profiel van A niet');
select is_empty($$
  update public.profiles set weight_kg = 99, updated_at = '2030-01-01 00:00:00+00'
  where id = '11111111-1111-1111-1111-111111111111' returning id
$$, 'B kan het profiel van A niet wijzigen');
select throws_ok($$
  insert into public.profiles (
    id, health_consent_at, health_consent_version, birth_date, sex, height_cm, weight_kg,
    activity_level, goal, kcal_target, protein_target_g, carbs_target_g, fat_target_g, updated_at
  ) values (
    '11111111-1111-1111-1111-111111111111', now(), 1, '1990-01-01', 'female', 165, 65,
    'light', 'lose', 1450, 130, 143, 40, now()
  )
$$, '42501', null, 'B kan geen profiel aanmaken met het id van A');
select throws_ok($$
  insert into public.profiles (
    id, health_consent_at, health_consent_version, birth_date, sex, height_cm, weight_kg,
    activity_level, goal, kcal_target, protein_target_g, carbs_target_g, fat_target_g, updated_at
  ) values (
    '22222222-2222-2222-2222-222222222222', now(), 1, (current_date - interval '17 years')::date, 'female', 165, 65,
    'light', 'lose', 1450, 130, 143, 40, now()
  )
$$, '23514', null, 'een geboortedatum onder de 18 wordt geweigerd');
select lives_ok($$
  insert into public.profiles (
    id, health_consent_at, health_consent_version, birth_date, sex, height_cm, weight_kg,
    activity_level, goal, kcal_target, protein_target_g, carbs_target_g, fat_target_g, updated_at
  ) values (
    '22222222-2222-2222-2222-222222222222', now(), 1, (current_date - interval '18 years')::date, 'female', 165, 65,
    'light', 'lose', 1450, 130, 143, 40, now()
  )
$$, 'precies 18 jaar is toegestaan');

-- Niet ingelogd
reset role;
set local role anon;
select is_empty('select id from public.profiles', 'anon ziet geen profielen');

select * from finish();
rollback;

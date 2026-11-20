begin;
create extension if not exists pgtap with schema extensions;
select plan(2);

insert into auth.users (id, email) values
  ('44444444-4444-4444-4444-444444444444', 'd@example.test'),
  ('55555555-5555-5555-5555-555555555555', 'e@example.test');

select lives_ok($$
  insert into public.creatures (user_id, species, name, color_index, tone, created_on, body_shape, updated_at)
  values ('44444444-4444-4444-4444-444444444444', 'owl', 'Uil', 0, 'sweet', '2026-11-20', 0.3, now())
$$, 'een van de zestien soorten mag');

select throws_ok($$
  insert into public.creatures (user_id, species, name, color_index, tone, created_on, body_shape, updated_at)
  values ('55555555-5555-5555-5555-555555555555', 'sprout', 'Sprout', 0, 'sweet', '2026-11-20', 0.3, now())
$$, '23514', null, 'een soort van voor de 3D-partners mag niet meer');

select * from finish();
rollback;

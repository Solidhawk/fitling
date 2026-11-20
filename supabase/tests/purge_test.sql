begin;
create extension if not exists pgtap with schema extensions;
select plan(6);

insert into auth.users (id, email) values ('33333333-3333-3333-3333-333333333333', 'c@example.test');

-- synced_at wordt door de trigger altijd op nu gezet; zonder triggers kan de test een oude waarde zetten.
set local session_replication_role = replica;
insert into public.water_entries (id, user_id, consumed_on, amount_ml, updated_at, synced_at, deleted_at) values
  ('a0000000-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', '2026-01-01', 250,
   now() - interval '200 days', now() - interval '91 days', now() - interval '200 days'),
  ('a0000000-0000-0000-0000-000000000002', '33333333-3333-3333-3333-333333333333', '2026-01-01', 250,
   now() - interval '200 days', now() - interval '89 days', now() - interval '200 days'),
  ('a0000000-0000-0000-0000-000000000003', '33333333-3333-3333-3333-333333333333', '2026-01-01', 250,
   now() - interval '400 days', now() - interval '400 days', null);
set local session_replication_role = origin;

select ok(private.purge_deletion_markers() >= 1, 'de job geeft het aantal verwijderde rijen');
select is(
  (select count(*) from public.water_entries where id = 'a0000000-0000-0000-0000-000000000001'), 0::bigint,
  'een markering die meer dan 90 dagen geleden gesynct is, verdwijnt'
);
select is(
  (select count(*) from public.water_entries where id = 'a0000000-0000-0000-0000-000000000002'), 1::bigint,
  'de 90 dagen tellen vanaf synced_at, niet vanaf deleted_at'
);
select is(
  (select count(*) from public.water_entries where id = 'a0000000-0000-0000-0000-000000000003'), 1::bigint,
  'een rij zonder markering blijft, hoe oud ook'
);
select is(private.purge_deletion_markers(), 0, 'een tweede keer is er niets meer te doen');

set local role authenticated;
set local request.jwt.claims = '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
select throws_ok(
  'select private.purge_deletion_markers()', '42501', null,
  'een gebruiker kan de job niet aanroepen'
);

select * from finish();
rollback;

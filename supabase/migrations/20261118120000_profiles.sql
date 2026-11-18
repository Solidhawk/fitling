create schema if not exists private;

-- Laatste wijziging wint op updated_at (klok van de client).
-- synced_at is de klok van de server en dient vanaf fase 2 als pull-cursor.
create function private.apply_sync_rules()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and new.updated_at < old.updated_at then
    return null;
  end if;
  new.synced_at := now();
  return new;
end;
$$;

create table public.profiles (
  id                     uuid primary key references auth.users (id) on delete cascade,
  health_consent_at      timestamptz not null,
  health_consent_version integer not null check (health_consent_version > 0),
  -- Vergelijken met current_date wordt alleen gecontroleerd bij insert/update;
  -- dat volstaat omdat iemand alleen ouder wordt.
  birth_date             date not null check (
                           birth_date >= date '1900-01-01'
                           and birth_date <= (current_date - interval '18 years')::date
                         ),
  sex                    text not null check (sex in ('male', 'female', 'other')),
  height_cm              numeric(4,1) not null check (height_cm between 100 and 250),
  weight_kg              numeric(4,1) not null check (weight_kg between 30 and 350),
  activity_level         text not null check (activity_level in ('sedentary', 'light', 'moderate', 'active', 'very_active')),
  goal                   text not null check (goal in ('lose', 'build_muscle', 'maintain', 'recomp')),
  kcal_target            integer not null check (kcal_target between 1 and 20000),
  protein_target_g       integer not null check (protein_target_g between 0 and 1000),
  carbs_target_g         integer not null check (carbs_target_g between 0 and 5000),
  fat_target_g           integer not null check (fat_target_g between 0 and 2000),
  targets_are_manual     boolean not null default false,
  updated_at             timestamptz not null,
  synced_at              timestamptz not null default now()
);

create trigger profiles_apply_sync_rules
  before insert or update on public.profiles
  for each row execute function private.apply_sync_rules();

alter table public.profiles enable row level security;

create policy "profiles: eigen rij lezen" on public.profiles
  for select to authenticated
  using ((select auth.uid()) = id);

create policy "profiles: eigen rij aanmaken" on public.profiles
  for insert to authenticated
  with check ((select auth.uid()) = id);

create policy "profiles: eigen rij wijzigen" on public.profiles
  for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);
-- Geen delete-policy: een profiel verdwijnt alleen via account verwijderen (cascade).

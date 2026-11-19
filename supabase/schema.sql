-- Fitling: het volledige databaseschema.
--
-- Dit bestand is de enige bron van het schema zolang er geen productiedatabase is
-- (docs/ARCHITECTURE.md, beslissing D-07). CI zet het op een lege database en draait de
-- pgTAP-tests in supabase/tests/.
--
-- Vaste regels:
--   * Elke tabel heeft RLS. Wat van een gebruiker is, kan alleen die gebruiker lezen en schrijven.
--   * Gedeelde data (producten, oefeningen, recepten, aanbiedingen) is voor iedereen leesbaar en
--     wordt alleen geschreven door Edge Functions met de geheime sleutel.
--   * Sync: updated_at is de klok van de client (laatste wijziging wint), synced_at is de klok van
--     de server (pull-cursor), deleted_at markeert een verwijderde rij.
--   * Rijen die een toestel offline aanmaakt, hebben een uuid van dat toestel als sleutel en geen
--     andere unieke eis: twee toestellen die offline hetzelfde doen, mogen nooit botsen.

create schema if not exists private;
create extension if not exists pg_trgm with schema extensions;

-- ---------------------------------------------------------------------------------------------
-- Sync
-- ---------------------------------------------------------------------------------------------

-- Laatste wijziging wint op updated_at; een oudere update wordt genegeerd.
-- synced_at wordt altijd door de server gezet, wat de client ook meestuurt.
-- Een updated_at uit de toekomst wordt teruggezet naar nu: een toestel waarvan de klok
-- voorloopt, zou anders elke latere wijziging van een ander toestel blijven overschrijven.
create function private.apply_sync_rules()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.updated_at > now() + interval '5 minutes' then
    new.updated_at := now();
  end if;
  if tg_op = 'UPDATE' and new.updated_at < old.updated_at then
    return null;
  end if;
  new.synced_at := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- Fase 1: profiel en doelen
-- ---------------------------------------------------------------------------------------------

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
  -- Trainingen uit HealthKit verhogen het dagbudget. De trainingen zelf blijven op het toestel.
  counts_workout_energy  boolean not null default false,
  postal_code            text check (char_length(postal_code) between 4 and 10),
  updated_at             timestamptz not null,
  synced_at              timestamptz not null default now()
);

-- De doelen per periode. Het wezentje en het dagoverzicht vergelijken een dag met het doel dat
-- toen gold, niet met het doel van vandaag.
create table public.target_history (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users (id) on delete cascade,
  effective_on     date not null,
  kcal_target      integer not null check (kcal_target between 1 and 20000),
  protein_target_g integer not null check (protein_target_g between 0 and 1000),
  carbs_target_g   integer not null check (carbs_target_g between 0 and 5000),
  fat_target_g     integer not null check (fat_target_g between 0 and 2000),
  updated_at       timestamptz not null,
  synced_at        timestamptz not null default now(),
  deleted_at       timestamptz
);

-- ---------------------------------------------------------------------------------------------
-- Fase 2: producten en voeding
-- ---------------------------------------------------------------------------------------------

-- Gedeelde productcache (owner_id is null) en eigen producten van een gebruiker (owner_id gezet).
-- Eén tabel, zodat een voedingslog altijd naar één soort product verwijst.
create table public.products (
  id                uuid primary key default gen_random_uuid(),
  owner_id          uuid references auth.users (id) on delete cascade,
  source            text not null check (source in ('off', 'nevo', 'user', 'fatsecret', 'nutritionix')),
  source_id         text,
  -- Genormaliseerd: EAN-8 als 8 cijfers, EAN-13 als 13 cijfers, UPC-A als 13 cijfers met een 0 ervoor
  -- (FitlingCore.Barcode). Zo levert dezelfde verpakking altijd dezelfde sleutel op.
  gtin              text check (gtin ~ '^([0-9]{8}|[0-9]{13})$'),
  -- Naam per taal: {"nl": "Volkorenbrood", "en": "Wholemeal bread"}.
  name              jsonb not null check (jsonb_typeof(name) = 'object' and name <> '{}'::jsonb),
  brand             text,
  -- Kleine letters, zonder accenten: alle namen en het merk achter elkaar. Gevuld door wie de rij schrijft.
  search_name       text not null default '',
  -- Voedingswaarden gelden per 100 g of per 100 ml.
  quantity_unit     text not null default 'g' check (quantity_unit in ('g', 'ml')),
  serving_size      numeric(7,2) check (serving_size > 0),
  serving_label     text,
  -- Leeg = onbekend. Een product zonder kcal kan pas gelogd worden als de gebruiker het aanvult.
  kcal_100          numeric(6,1) check (kcal_100 between 0 and 900),
  protein_100       numeric(5,2) check (protein_100 between 0 and 100),
  carbs_100         numeric(5,2) check (carbs_100 between 0 and 100),
  sugars_100        numeric(5,2) check (sugars_100 between 0 and 100),
  fat_100           numeric(5,2) check (fat_100 between 0 and 100),
  saturated_fat_100 numeric(5,2) check (saturated_fat_100 between 0 and 100),
  fiber_100         numeric(5,2) check (fiber_100 between 0 and 100),
  salt_100          numeric(5,2) check (salt_100 between 0 and 100),
  image_url         text,
  -- Door ons nagekeken, of afkomstig van NEVO.
  is_verified       boolean not null default false,
  -- Wanneer de externe bron voor het laatst is gelezen; bepaalt wanneer de cache ververst wordt.
  fetched_at        timestamptz,
  updated_at        timestamptz not null,
  synced_at         timestamptz not null default now(),
  deleted_at        timestamptz,
  check ((owner_id is null) or (source = 'user'))
);

-- Dubbele producten voorkomen: per barcode en per bronrecord hoogstens één gedeelde rij.
create unique index products_shared_gtin on public.products (gtin) where owner_id is null and gtin is not null;
create unique index products_shared_source on public.products (source, source_id) where owner_id is null and source_id is not null;
create index products_owner on public.products (owner_id, synced_at) where owner_id is not null;
create index products_search on public.products using gin (search_name extensions.gin_trgm_ops);

-- Wat een gebruiker instuurt voor een barcode die nergens gevonden is. De Edge Function
-- submit-product controleert de waarden en maakt of verbetert daarmee de gedeelde rij.
create table public.product_submissions (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  gtin          text not null check (gtin ~ '^([0-9]{8}|[0-9]{13})$'),
  payload       jsonb not null check (jsonb_typeof(payload) = 'object'),
  package_photo text,
  label_photo   text,
  status        text not null default 'pending' check (status in ('pending', 'accepted', 'rejected')),
  product_id    uuid references public.products (id) on delete set null,
  created_at    timestamptz not null default now()
);
create index product_submissions_user on public.product_submissions (user_id);

-- ---------------------------------------------------------------------------------------------
-- Fase 5 (hier, omdat food_entries ernaar verwijst): recepten
-- ---------------------------------------------------------------------------------------------

create table public.recipes (
  id                    uuid primary key default gen_random_uuid(),
  owner_id              uuid references auth.users (id) on delete cascade,
  title                 jsonb not null check (jsonb_typeof(title) = 'object' and title <> '{}'::jsonb),
  -- Per taal een lijst stappen: {"nl": ["Snijd de ui.", "Bak hem glazig."]}.
  steps                 jsonb not null default '{}'::jsonb check (jsonb_typeof(steps) = 'object'),
  servings              integer not null check (servings between 1 and 20),
  cook_minutes          integer not null check (cook_minutes between 0 and 600),
  kcal_per_serving      numeric(6,1) not null check (kcal_per_serving between 0 and 5000),
  protein_g_per_serving numeric(5,1) not null check (protein_g_per_serving between 0 and 500),
  carbs_g_per_serving   numeric(5,1) not null check (carbs_g_per_serving between 0 and 1000),
  fat_g_per_serving     numeric(5,1) not null check (fat_g_per_serving between 0 and 500),
  -- Leeg = prijs onbekend; telt dan niet mee in het budget.
  cost_cents_per_serving integer check (cost_cents_per_serving between 0 and 100000),
  -- Geschikt om één keer te koken en twee dagen te eten.
  keeps_well            boolean not null default false,
  meal_slots            text[] not null check (
                          cardinality(meal_slots) > 0
                          and meal_slots <@ array['breakfast', 'lunch', 'dinner', 'snack']
                        ),
  -- Wat het recept bevat, voor uitsluitingen: 'meat', 'fish', 'dairy', 'gluten', 'nuts', ...
  tags                  text[] not null default '{}',
  image_url             text,
  updated_at            timestamptz not null,
  synced_at             timestamptz not null default now(),
  deleted_at            timestamptz
);
create index recipes_owner on public.recipes (owner_id, synced_at) where owner_id is not null;
create index recipes_shared on public.recipes (synced_at) where owner_id is null;

create table public.recipe_ingredients (
  id         uuid primary key default gen_random_uuid(),
  recipe_id  uuid not null references public.recipes (id) on delete cascade,
  -- Gelijk aan de eigenaar van het recept; hier herhaald zodat RLS en sync geen join nodig hebben.
  owner_id   uuid references auth.users (id) on delete cascade,
  product_id uuid references public.products (id) on delete set null,
  name       jsonb not null check (jsonb_typeof(name) = 'object' and name <> '{}'::jsonb),
  quantity   numeric(8,2) not null check (quantity > 0),
  unit       text not null check (unit in ('g', 'ml', 'piece', 'tbsp', 'tsp')),
  aisle      text not null default 'other' check (aisle in (
               'produce', 'bakery', 'meat_fish', 'dairy', 'frozen', 'pantry', 'drinks', 'household', 'other'
             )),
  position   integer not null default 0,
  updated_at timestamptz not null,
  synced_at  timestamptz not null default now(),
  deleted_at timestamptz
);
create index recipe_ingredients_recipe on public.recipe_ingredients (recipe_id);

-- ---------------------------------------------------------------------------------------------
-- Fase 2 (vervolg): voedingslog, water, favorieten
-- ---------------------------------------------------------------------------------------------

create table public.food_entries (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  -- De dag zoals de gebruiker hem beleefde; geen tijdstip, zodat reizen een maaltijd niet verschuift.
  consumed_on   date not null,
  meal          text not null check (meal in ('breakfast', 'lunch', 'dinner', 'snack')),
  product_id    uuid references public.products (id) on delete set null,
  recipe_id     uuid references public.recipes (id) on delete set null,
  -- Momentopname: naam en waarden zoals ze waren bij het loggen. Een bijgewerkt product
  -- verandert oude dagen dus niet.
  name          text not null check (char_length(name) between 1 and 200),
  quantity      numeric(7,1) not null check (quantity > 0 and quantity <= 10000),
  quantity_unit text not null check (quantity_unit in ('g', 'ml', 'serving')),
  kcal          numeric(7,1) not null check (kcal between 0 and 20000),
  -- Leeg = onbekend bij het product; telt als 0 en wordt in het dagoverzicht gemeld.
  protein_g     numeric(6,1) check (protein_g between 0 and 2000),
  carbs_g       numeric(6,1) check (carbs_g between 0 and 5000),
  fat_g         numeric(6,1) check (fat_g between 0 and 2000),
  updated_at    timestamptz not null,
  synced_at     timestamptz not null default now(),
  deleted_at    timestamptz
);
create index food_entries_day on public.food_entries (user_id, consumed_on);

-- Losse slokken in plaats van één dagtotaal: twee toestellen die offline water loggen,
-- tellen dan gewoon op.
create table public.water_entries (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  consumed_on date not null,
  amount_ml   integer not null check (amount_ml between 1 and 5000),
  updated_at  timestamptz not null,
  synced_at   timestamptz not null default now(),
  deleted_at  timestamptz
);
create index water_entries_day on public.water_entries (user_id, consumed_on);

-- "Recent" is geen tabel: dat volgt uit food_entries.
create table public.favorite_products (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users (id) on delete cascade,
  product_id uuid not null references public.products (id) on delete cascade,
  updated_at timestamptz not null,
  synced_at  timestamptz not null default now(),
  deleted_at timestamptz
);

-- ---------------------------------------------------------------------------------------------
-- Fase 3: het wezentje
-- ---------------------------------------------------------------------------------------------

-- Alleen wat bewaard moet blijven. Toestand, stemming en groei rekent FitlingCore.CreatureEngine
-- op het toestel uit de logs.
create table public.creatures (
  user_id           uuid primary key references auth.users (id) on delete cascade,
  species           text not null check (species in ('sprout', 'ember', 'pip', 'pebble')),
  name              text not null check (char_length(name) between 1 and 24),
  color_index       integer not null check (color_index between 0 and 9),
  tone              text not null check (tone in ('sweet', 'funny', 'coach')),
  created_on        date not null,
  body_shape        numeric(4,3) not null check (body_shape between 0 and 1),
  xp                integer not null default 0 check (xp >= 0),
  last_processed_on date,
  off_target_days   integer not null default 0 check (off_target_days >= 0),
  equipped_items    text[] not null default '{}' check (
                      equipped_items <@ array['scarf', 'cap', 'bow', 'glasses', 'backpack', 'crown']
                    ),
  updated_at        timestamptz not null,
  synced_at         timestamptz not null default now()
);

-- ---------------------------------------------------------------------------------------------
-- Fase 4: sport
-- ---------------------------------------------------------------------------------------------

-- Gedeelde oefeningen (owner_id is null) en eigen oefeningen.
create table public.exercises (
  id                uuid primary key default gen_random_uuid(),
  owner_id          uuid references auth.users (id) on delete cascade,
  name              jsonb not null check (jsonb_typeof(name) = 'object' and name <> '{}'::jsonb),
  instructions      jsonb not null default '{}'::jsonb check (jsonb_typeof(instructions) = 'object'),
  kind              text not null check (kind in ('compound', 'isolation')),
  load_type         text not null check (load_type in ('external', 'bodyweight')),
  equipment         text not null check (equipment in (
                      'barbell', 'dumbbell', 'machine', 'cable', 'kettlebell', 'band', 'bodyweight', 'other'
                    )),
  primary_muscles   text[] not null check (
                      cardinality(primary_muscles) > 0
                      and primary_muscles <@ array['chest', 'back', 'shoulders', 'biceps', 'triceps', 'forearms',
                                                   'core', 'glutes', 'quads', 'hamstrings', 'calves']
                    ),
  secondary_muscles text[] not null default '{}' check (
                      secondary_muscles <@ array['chest', 'back', 'shoulders', 'biceps', 'triceps', 'forearms',
                                                 'core', 'glutes', 'quads', 'hamstrings', 'calves']
                    ),
  -- De kleinste gewichtsstap voor dit soort materiaal; de gebruiker kan hem per oefening aanpassen.
  default_step_kg   numeric(4,2) not null check (default_step_kg > 0 and default_step_kg <= 25),
  image_url         text,
  updated_at        timestamptz not null,
  synced_at         timestamptz not null default now(),
  deleted_at        timestamptz
);
create index exercises_owner on public.exercises (owner_id, synced_at) where owner_id is not null;

-- Kant-en-klare schema's (owner_id is null) en eigen schema's.
create table public.programs (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid references auth.users (id) on delete cascade,
  name          jsonb not null check (jsonb_typeof(name) = 'object' and name <> '{}'::jsonb),
  days_per_week integer not null check (days_per_week between 1 and 7),
  updated_at    timestamptz not null,
  synced_at     timestamptz not null default now(),
  deleted_at    timestamptz
);

create table public.program_days (
  id         uuid primary key default gen_random_uuid(),
  program_id uuid not null references public.programs (id) on delete cascade,
  owner_id   uuid references auth.users (id) on delete cascade,
  name       jsonb not null check (jsonb_typeof(name) = 'object' and name <> '{}'::jsonb),
  position   integer not null default 0,
  updated_at timestamptz not null,
  synced_at  timestamptz not null default now(),
  deleted_at timestamptz
);
create index program_days_program on public.program_days (program_id);

create table public.program_exercises (
  id             uuid primary key default gen_random_uuid(),
  program_day_id uuid not null references public.program_days (id) on delete cascade,
  owner_id       uuid references auth.users (id) on delete cascade,
  exercise_id    uuid not null references public.exercises (id) on delete cascade,
  position       integer not null default 0,
  target_sets    integer not null check (target_sets between 1 and 10),
  rep_min        integer not null check (rep_min between 1 and 100),
  rep_max        integer not null check (rep_max between 1 and 100),
  rest_seconds   integer not null default 120 check (rest_seconds between 0 and 900),
  updated_at     timestamptz not null,
  synced_at      timestamptz not null default now(),
  deleted_at     timestamptz,
  check (rep_min <= rep_max)
);
create index program_exercises_day on public.program_exercises (program_day_id);

-- Eigen gewichtsstap en rep-range per oefening (dumbbells per 2 kg, machine per 5 kg).
create table public.exercise_settings (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  exercise_id uuid not null references public.exercises (id) on delete cascade,
  step_kg     numeric(4,2) not null check (step_kg > 0 and step_kg <= 25),
  rep_min     integer check (rep_min between 1 and 100),
  rep_max     integer check (rep_max between 1 and 100),
  updated_at  timestamptz not null,
  synced_at   timestamptz not null default now(),
  deleted_at  timestamptz,
  check (rep_min is null or rep_max is null or rep_min <= rep_max)
);

create table public.workout_sessions (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users (id) on delete cascade,
  program_day_id uuid references public.program_days (id) on delete set null,
  performed_on   date not null,
  started_at     timestamptz not null,
  ended_at       timestamptz,
  note           text check (char_length(note) <= 500),
  updated_at     timestamptz not null,
  synced_at      timestamptz not null default now(),
  deleted_at     timestamptz,
  check (ended_at is null or ended_at >= started_at)
);
create index workout_sessions_day on public.workout_sessions (user_id, performed_on);

create table public.workout_sets (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  session_id  uuid not null references public.workout_sessions (id) on delete cascade,
  exercise_id uuid not null references public.exercises (id) on delete cascade,
  position    integer not null default 0,
  -- Bij een oefening met lichaamsgewicht: alleen het extra gewicht, 0 voor geen.
  weight_kg   numeric(6,2) not null check (weight_kg between 0 and 1000),
  reps        integer not null check (reps between 0 and 1000),
  rpe         numeric(3,1) check (rpe between 1 and 10),
  is_warmup   boolean not null default false,
  updated_at  timestamptz not null,
  synced_at   timestamptz not null default now(),
  deleted_at  timestamptz
);
create index workout_sets_session on public.workout_sets (session_id);
create index workout_sets_exercise on public.workout_sets (user_id, exercise_id);

-- Lichaamsgewicht en omtrekken. Progressiefoto's staan hier bewust niet: die verlaten het toestel nooit.
create table public.body_measurements (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  measured_on date not null,
  kind        text not null check (kind in ('weight', 'waist', 'chest', 'hips', 'arm', 'thigh', 'neck')),
  -- kg voor 'weight', cm voor de rest.
  value       numeric(5,1) not null check (value > 0 and value <= 500),
  updated_at  timestamptz not null,
  synced_at   timestamptz not null default now(),
  deleted_at  timestamptz
);
create index body_measurements_day on public.body_measurements (user_id, measured_on);

-- ---------------------------------------------------------------------------------------------
-- Fase 5: weekmenu
-- ---------------------------------------------------------------------------------------------

create table public.menu_preferences (
  user_id          uuid primary key references auth.users (id) on delete cascade,
  excluded_tags    text[] not null default '{}',
  max_cook_minutes integer check (max_cook_minutes between 5 and 600),
  budget_cents     integer check (budget_cents between 0 and 1000000),
  meal_prep        boolean not null default false,
  meal_slots       text[] not null default array['breakfast', 'lunch', 'dinner'] check (
                     cardinality(meal_slots) > 0
                     and meal_slots <@ array['breakfast', 'lunch', 'dinner', 'snack']
                   ),
  updated_at       timestamptz not null,
  synced_at        timestamptz not null default now()
);

-- Ingrediënten die de gebruiker niet wil in het weekmenu.
create table public.excluded_ingredients (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users (id) on delete cascade,
  product_id uuid not null references public.products (id) on delete cascade,
  updated_at timestamptz not null,
  synced_at  timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.meal_plan_entries (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users (id) on delete cascade,
  planned_on      date not null,
  meal            text not null check (meal in ('breakfast', 'lunch', 'dinner', 'snack')),
  recipe_id       uuid not null references public.recipes (id) on delete cascade,
  servings        numeric(4,2) not null check (servings > 0 and servings <= 10),
  -- De dag ervoor gekookt.
  is_leftover     boolean not null default false,
  -- Door de gebruiker vastgezet; de planner laat deze staan.
  is_pinned       boolean not null default false,
  -- Gezet zodra de maaltijd met één tik is gelogd, zodat hij niet twee keer gelogd wordt.
  logged_entry_id uuid references public.food_entries (id) on delete set null,
  updated_at      timestamptz not null,
  synced_at       timestamptz not null default now(),
  deleted_at      timestamptz
);
create index meal_plan_entries_day on public.meal_plan_entries (user_id, planned_on);

-- ---------------------------------------------------------------------------------------------
-- Fase 6: boodschappenlijst (gedeeld) en aanbiedingen
-- ---------------------------------------------------------------------------------------------

create table public.shopping_lists (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (char_length(name) between 1 and 60),
  -- Wie de lijst maakte. Leeg zodra die persoon de lijst verlaat of het account verwijdert.
  created_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null,
  synced_at  timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.shopping_list_members (
  list_id      uuid not null references public.shopping_lists (id) on delete cascade,
  user_id      uuid not null references auth.users (id) on delete cascade,
  role         text not null check (role in ('owner', 'member')),
  -- De naam die huisgenoten zien. Profielen zijn privé, dus de naam staat hier.
  display_name text not null check (char_length(display_name) between 1 and 40),
  joined_at    timestamptz not null default now(),
  primary key (list_id, user_id)
);
create index shopping_list_members_user on public.shopping_list_members (user_id);

-- Uitnodigingen. Alleen de hash van de code wordt bewaard; clients komen hier nooit bij,
-- alles loopt via de functies hieronder.
create table public.shopping_list_invites (
  id         uuid primary key default gen_random_uuid(),
  list_id    uuid not null references public.shopping_lists (id) on delete cascade,
  code_hash  text not null unique,
  created_by uuid references auth.users (id) on delete set null,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create table public.shopping_items (
  id         uuid primary key default gen_random_uuid(),
  list_id    uuid not null references public.shopping_lists (id) on delete cascade,
  name       text not null check (char_length(name) between 1 and 120),
  quantity   numeric(8,2) check (quantity > 0),
  unit       text check (unit in ('g', 'ml', 'piece', 'tbsp', 'tsp')),
  aisle      text not null default 'other' check (aisle in (
               'produce', 'bakery', 'meat_fish', 'dairy', 'frozen', 'pantry', 'drinks', 'household', 'other'
             )),
  product_id uuid references public.products (id) on delete set null,
  is_checked boolean not null default false,
  -- 'menu': door het weekmenu op de lijst gezet; wordt vervangen als het menu verandert.
  source     text not null default 'manual' check (source in ('manual', 'menu')),
  updated_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null,
  synced_at  timestamptz not null default now(),
  deleted_at timestamptz
);
create index shopping_items_list on public.shopping_items (list_id, synced_at);

create table public.supermarkets (
  id         text primary key check (id ~ '^[a-z0-9_]{2,30}$'),
  name       text not null,
  updated_at timestamptz not null default now()
);

-- Alleen de backend schrijft hier (OfferProvider-job). De app leest en matcht zelf.
create table public.offers (
  id                  uuid primary key default gen_random_uuid(),
  supermarket_id      text not null references public.supermarkets (id) on delete cascade,
  -- Het id van de aanbieding bij de bron; met de winkel en de startdatum uniek.
  external_id         text not null,
  title               text not null,
  search_title        text not null default '',
  brand               text,
  gtin                text check (gtin ~ '^([0-9]{8}|[0-9]{13})$'),
  -- Inhoud van één verpakking, voor zover de bron die geeft.
  quantity_value      numeric(8,2) check (quantity_value > 0),
  quantity_unit       text check (quantity_unit in ('g', 'ml', 'piece')),
  price_cents         integer not null check (price_cents >= 0),
  regular_price_cents integer check (regular_price_cents >= 0),
  -- Zoals de winkel het noemt: "1+1 gratis", "2 voor 3,00".
  promo_label         text,
  valid_from          date not null,
  valid_to            date not null,
  image_url           text,
  fetched_at          timestamptz not null default now(),
  synced_at           timestamptz not null default now(),
  unique (supermarket_id, external_id, valid_from),
  check (valid_to >= valid_from)
);
create index offers_valid on public.offers (supermarket_id, valid_to);
create index offers_gtin on public.offers (gtin) where gtin is not null;

create table public.favorite_supermarkets (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users (id) on delete cascade,
  supermarket_id text not null references public.supermarkets (id) on delete cascade,
  updated_at     timestamptz not null,
  synced_at      timestamptz not null default now(),
  deleted_at     timestamptz
);

-- Tellers voor Edge Functions die een betaalde of beperkte bron aanroepen.
create table private.rate_limits (
  bucket       text not null,
  window_start timestamptz not null,
  count        integer not null default 1,
  primary key (bucket, window_start)
);
alter table private.rate_limits enable row level security;

-- ---------------------------------------------------------------------------------------------
-- Sync-triggers
-- ---------------------------------------------------------------------------------------------

do $$
declare
  t text;
begin
  foreach t in array array[
    'profiles', 'target_history', 'products', 'recipes', 'recipe_ingredients', 'food_entries',
    'water_entries', 'favorite_products', 'creatures', 'exercises', 'programs', 'program_days',
    'program_exercises', 'exercise_settings', 'workout_sessions', 'workout_sets', 'body_measurements',
    'menu_preferences', 'excluded_ingredients', 'meal_plan_entries', 'shopping_lists', 'shopping_items',
    'favorite_supermarkets'
  ] loop
    execute format(
      'create trigger %I before insert or update on public.%I for each row execute function private.apply_sync_rules()',
      t || '_apply_sync_rules', t
    );
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- RLS: privédata. Alleen de eigenaar leest en schrijft. Geen delete-policy: verwijderen is
-- deleted_at zetten; echt verdwijnen gebeurt alleen bij account verwijderen (cascade).
-- ---------------------------------------------------------------------------------------------

do $$
declare
  t text;
begin
  foreach t in array array[
    'target_history', 'food_entries', 'water_entries', 'favorite_products', 'creatures',
    'exercise_settings', 'workout_sessions', 'workout_sets', 'body_measurements',
    'menu_preferences', 'excluded_ingredients', 'meal_plan_entries', 'favorite_supermarkets'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format(
      'create policy %I on public.%I for select to authenticated using ((select auth.uid()) = user_id)',
      t || ': eigen rijen lezen', t
    );
    execute format(
      'create policy %I on public.%I for insert to authenticated with check ((select auth.uid()) = user_id)',
      t || ': eigen rijen aanmaken', t
    );
    execute format(
      'create policy %I on public.%I for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id)',
      t || ': eigen rijen wijzigen', t
    );
  end loop;
end;
$$;

alter table public.profiles enable row level security;
create policy "profiles: eigen rij lezen" on public.profiles
  for select to authenticated using ((select auth.uid()) = id);
create policy "profiles: eigen rij aanmaken" on public.profiles
  for insert to authenticated with check ((select auth.uid()) = id);
create policy "profiles: eigen rij wijzigen" on public.profiles
  for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

alter table public.product_submissions enable row level security;
create policy "product_submissions: eigen rijen lezen" on public.product_submissions
  for select to authenticated using ((select auth.uid()) = user_id);
-- Insturen gaat via de Edge Function submit-product; er is bewust geen insert-policy.

-- ---------------------------------------------------------------------------------------------
-- RLS: gedeelde catalogi met eigen rijen. Iedereen leest de gedeelde rijen (owner_id is null);
-- alleen de eigenaar leest en schrijft eigen rijen. Gedeelde rijen schrijft alleen de backend.
-- ---------------------------------------------------------------------------------------------

do $$
declare
  t text;
begin
  foreach t in array array['products', 'recipes', 'recipe_ingredients', 'exercises', 'programs', 'program_days', 'program_exercises'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format(
      'create policy %I on public.%I for select to authenticated using (owner_id is null or (select auth.uid()) = owner_id)',
      t || ': gedeeld en eigen lezen', t
    );
    execute format(
      'create policy %I on public.%I for insert to authenticated with check ((select auth.uid()) = owner_id)',
      t || ': eigen rijen aanmaken', t
    );
    execute format(
      'create policy %I on public.%I for update to authenticated using ((select auth.uid()) = owner_id) with check ((select auth.uid()) = owner_id)',
      t || ': eigen rijen wijzigen', t
    );
  end loop;
end;
$$;

alter table public.supermarkets enable row level security;
create policy "supermarkets: iedereen leest" on public.supermarkets
  for select to authenticated using (true);

alter table public.offers enable row level security;
create policy "offers: iedereen leest" on public.offers
  for select to authenticated using (true);

-- ---------------------------------------------------------------------------------------------
-- RLS: gedeelde boodschappenlijst
-- ---------------------------------------------------------------------------------------------

-- In een functie, omdat een policy op shopping_list_members die zelf shopping_list_members
-- leest, zichzelf zou aanroepen.
create function private.is_list_member(list uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.shopping_list_members
    where list_id = list and user_id = (select auth.uid())
  );
$$;

create function private.is_list_owner(list uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.shopping_list_members
    where list_id = list and user_id = (select auth.uid()) and role = 'owner'
  );
$$;

alter table public.shopping_lists enable row level security;
-- De maker ziet de lijst ook vóór hij zichzelf als lid heeft toegevoegd (offline aangemaakt,
-- twee losse pushes).
create policy "shopping_lists: leden lezen" on public.shopping_lists
  for select to authenticated
  using (private.is_list_member(id) or (select auth.uid()) = created_by);
create policy "shopping_lists: zelf aanmaken" on public.shopping_lists
  for insert to authenticated
  with check ((select auth.uid()) = created_by);
create policy "shopping_lists: leden wijzigen" on public.shopping_lists
  for update to authenticated
  using (private.is_list_member(id))
  with check (private.is_list_member(id));

alter table public.shopping_list_members enable row level security;
create policy "shopping_list_members: leden lezen" on public.shopping_list_members
  for select to authenticated
  using (private.is_list_member(list_id));
-- Alleen de maker kan zichzelf toevoegen, als eigenaar. Alle anderen komen binnen via
-- join_shopping_list met een uitnodigingscode.
create policy "shopping_list_members: maker wordt eigenaar" on public.shopping_list_members
  for insert to authenticated
  with check (
    (select auth.uid()) = user_id
    and role = 'owner'
    and exists (
      select 1 from public.shopping_lists
      where id = list_id and created_by = (select auth.uid())
    )
  );
create policy "shopping_list_members: zelf weggaan of eigenaar verwijdert" on public.shopping_list_members
  for delete to authenticated
  using ((select auth.uid()) = user_id or private.is_list_owner(list_id));

alter table public.shopping_list_invites enable row level security;
-- Geen policies: alleen de functies hieronder komen bij uitnodigingen.

alter table public.shopping_items enable row level security;
create policy "shopping_items: leden lezen" on public.shopping_items
  for select to authenticated
  using (private.is_list_member(list_id));
create policy "shopping_items: leden aanmaken" on public.shopping_items
  for insert to authenticated
  with check (private.is_list_member(list_id) and (select auth.uid()) = updated_by);
create policy "shopping_items: leden wijzigen" on public.shopping_items
  for update to authenticated
  using (private.is_list_member(list_id))
  with check (private.is_list_member(list_id) and (select auth.uid()) = updated_by);

-- Een lijst zonder leden verdwijnt. Gaat de eigenaar weg, dan wordt het langst aanwezige lid
-- eigenaar. Geldt ook als een account wordt verwijderd (cascade).
create function private.after_member_left()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.shopping_lists set created_by = null
  where id = old.list_id and created_by = old.user_id;

  if not exists (select 1 from public.shopping_list_members where list_id = old.list_id) then
    delete from public.shopping_lists where id = old.list_id;
  elsif not exists (select 1 from public.shopping_list_members where list_id = old.list_id and role = 'owner') then
    update public.shopping_list_members set role = 'owner'
    where list_id = old.list_id
      and user_id = (
        select user_id from public.shopping_list_members
        where list_id = old.list_id
        order by joined_at, user_id
        limit 1
      );
  end if;
  return null;
end;
$$;

create trigger shopping_list_members_after_delete
  after delete on public.shopping_list_members
  for each row execute function private.after_member_left();

-- Maakt een uitnodigingscode voor een lijst waar de aanroeper lid van is. De code is zeven
-- dagen geldig en wordt maar één keer getoond.
create function public.create_shopping_list_invite(list uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  code text;
begin
  if not private.is_list_member(list) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12));
  insert into public.shopping_list_invites (list_id, code_hash, created_by, expires_at)
  values (list, encode(sha256(convert_to(code, 'UTF8')), 'hex'), (select auth.uid()), now() + interval '7 days');
  return code;
end;
$$;

-- Wordt lid van de lijst bij de code. Geeft het id van de lijst terug.
create function public.join_shopping_list(invite_code text, member_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  target uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'not_signed_in' using errcode = '42501';
  end if;

  select list_id into target
  from public.shopping_list_invites
  where code_hash = encode(sha256(convert_to(upper(trim(invite_code)), 'UTF8')), 'hex')
    and expires_at > now();
  if target is null then
    raise exception 'invalid_invite' using errcode = 'P0002';
  end if;

  if (select count(*) from public.shopping_list_members where list_id = target) >= 10
     and not exists (select 1 from public.shopping_list_members where list_id = target and user_id = (select auth.uid())) then
    raise exception 'list_full' using errcode = 'P0001';
  end if;

  insert into public.shopping_list_members (list_id, user_id, role, display_name)
  values (target, (select auth.uid()), 'member', member_name)
  on conflict (list_id, user_id) do nothing;
  return target;
end;
$$;

revoke execute on function public.create_shopping_list_invite(uuid) from public, anon;
revoke execute on function public.join_shopping_list(text, text) from public, anon;
grant execute on function public.create_shopping_list_invite(uuid) to authenticated;
grant execute on function public.join_shopping_list(text, text) to authenticated;

-- Wijzigingen in de lijst komen direct bij huisgenoten binnen.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.shopping_lists, public.shopping_list_members, public.shopping_items;
  end if;
end;
$$;

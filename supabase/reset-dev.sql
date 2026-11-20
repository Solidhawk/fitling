-- Fitling: maakt het ontwikkelproject leeg, zodat supabase/schema.sql er opnieuw op kan.
--
-- Alleen voor het ontwikkelproject, zolang er geen productiedatabase is (docs/ARCHITECTURE.md,
-- beslissing D-07). Alle app-data verdwijnt. De accounts in auth.users blijven bestaan.
--
-- Gebruik: dit bestand, dan supabase/schema.sql. CI draait die twee na elkaar op een volledig
-- schema en controleert dat er daarna niets van het schema is overgebleven.
--
-- Ruimt ook de eerdere fase 1 op: die had alleen public.profiles en private.apply_sync_rules,
-- met dezelfde namen als hieronder.

-- Kinderen vóór ouders is niet nodig: cascade neemt verwijzingen, triggers en policies mee.
drop table if exists
  public.profiles,
  public.target_history,
  public.products,
  public.product_submissions,
  public.recipes,
  public.recipe_ingredients,
  public.food_entries,
  public.water_entries,
  public.favorite_products,
  public.creatures,
  public.exercises,
  public.programs,
  public.program_days,
  public.program_exercises,
  public.exercise_settings,
  public.workout_sessions,
  public.workout_sets,
  public.body_measurements,
  public.menu_preferences,
  public.excluded_ingredients,
  public.meal_plan_entries,
  public.shopping_lists,
  public.shopping_list_members,
  public.shopping_list_invites,
  public.shopping_items,
  public.supermarkets,
  public.offers,
  public.favorite_supermarkets,
  private.rate_limits
  cascade;

drop function if exists
  public.consume_rate_limit(text, integer),
  public.store_shared_product(jsonb),
  public.create_shopping_list_invite(uuid),
  public.join_shopping_list(text, text),
  private.apply_sync_rules(),
  private.is_list_member(uuid),
  private.is_list_owner(uuid),
  private.after_member_left(),
  private.purge_deletion_markers()
  cascade;

-- De nachtelijke opruimjob (fase 7), als pg_cron er is.
do $$
begin
  if to_regclass('cron.job') is not null then
    execute 'select cron.unschedule(jobid) from cron.job where jobname = ''purge-deletion-markers''';
  end if;
end;
$$;

-- De eerdere fase 1 kan met `supabase db push` zijn gezet; dan staat die migratie hier nog genoteerd.
do $$
begin
  if to_regclass('supabase_migrations.schema_migrations') is not null then
    delete from supabase_migrations.schema_migrations where version = '20261118120000';
  end if;
end;
$$;

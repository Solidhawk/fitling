-- Fitling: een product delen dat nergens bekend is (TASKS 2.8, ARCHITECTURE §5 stap 3).
--
-- Los van schema.sql, zodat dit op een project dat al draait kan: in de SQL Editor van Supabase plakken en
-- uitvoeren, vóór `supabase functions deploy submit-product` (docs/submit-product.md). Opnieuw uitvoeren kan.
-- CI zet het bovenop schema.sql en test het in tests/submit_product_test.sql.

-- Eén transactie voor de Edge Function submit-product: de inzending, de gedeelde rij en de status samen, zodat geen
-- van de drie los kan blijven staan. De eerste inzending voor een barcode wordt de gedeelde rij, nooit geverifieerd.
-- Een gedeelde rij die weggehaald was, komt terug met de nieuwe waarden; wie de rij maakte, mag hem verbeteren zolang
-- hij van een gebruiker komt. Elke andere inzending wacht. Een rij uit Open Food Facts verandert alleen door
-- lookup-product, die Open Food Facts ook vraagt voor een barcode met een rij van een gebruiker.
create or replace function public.submit_shared_product(p_user uuid, p_payload jsonb, p_product jsonb)
returns table (shared_id uuid, made_new boolean)
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.products;
  submission uuid;
  existing public.products;
  made uuid;
begin
  r := jsonb_populate_record(null::public.products, p_product);
  insert into public.product_submissions (user_id, gtin, payload)
  values (p_user, r.gtin, p_payload)
  returning id into submission;

  -- Twee tegelijk voor dezelfde barcode: de unieke index op gedeelde barcodes laat er één door.
  insert into public.products (
    source, gtin, name, brand, search_name, quantity_unit, serving_size, kcal_100, protein_100, carbs_100,
    sugars_100, fat_100, saturated_fat_100, fiber_100, salt_100, is_verified, updated_at
  ) values (
    'user', r.gtin, r.name, r.brand, r.search_name, r.quantity_unit, r.serving_size, r.kcal_100, r.protein_100,
    r.carbs_100, r.sugars_100, r.fat_100, r.saturated_fat_100, r.fiber_100, r.salt_100, false, now()
  )
  on conflict do nothing
  returning id into made;

  if made is not null then
    update public.product_submissions set status = 'accepted', product_id = made where id = submission;
    return query select made, true;
    return;
  end if;

  select * into existing from public.products p where p.gtin = r.gtin and p.owner_id is null for update;
  if existing.deleted_at is not null or (
    existing.source = 'user' and exists (
      select 1 from public.product_submissions s
      where s.product_id = existing.id and s.user_id = p_user and s.status = 'accepted'
    )
  ) then
    update public.products set
      source = 'user', source_id = null, name = r.name, brand = r.brand, search_name = r.search_name,
      quantity_unit = r.quantity_unit, serving_size = r.serving_size, kcal_100 = r.kcal_100,
      protein_100 = r.protein_100, carbs_100 = r.carbs_100, sugars_100 = r.sugars_100, fat_100 = r.fat_100,
      saturated_fat_100 = r.saturated_fat_100, fiber_100 = r.fiber_100, salt_100 = r.salt_100, image_url = null,
      is_verified = false, fetched_at = null, deleted_at = null,
      -- Later dan wat er staat, ook als dat van een klok kwam die voorliep: de syncregels houden het nieuwste.
      updated_at = greatest(now(), existing.updated_at + interval '1 millisecond')
    where id = existing.id;
    update public.product_submissions set status = 'accepted', product_id = existing.id where id = submission;
  end if;
  return query select existing.id, false;
end;
$$;

revoke all on function public.submit_shared_product(uuid, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.submit_shared_product(uuid, jsonb, jsonb) to service_role;

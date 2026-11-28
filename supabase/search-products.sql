-- Fitling: zoeken in de gedeelde producten, elk woord in elke volgorde en de beste treffer eerst.
--
-- Los van schema.sql, zodat dit op een project dat al draait kan: in de SQL Editor van Supabase plakken en uitvoeren,
-- vóór de app die het gebruikt live gaat. Opnieuw uitvoeren kan. CI zet het bovenop schema.sql en test het in
-- tests/search_products_test.sql.

-- NEVO draait namen om ("Melk halfvolle") en heeft veel treffers (docs/nevo.md): "halfvolle melk" moet "Melk
-- halfvolle" vinden, en "appel" eerst de appel en pas daarna "Aardappelen". De volgorde is die van
-- FoodLog.bestMatches, zodat de iPhone en de server gelijk rangschikken: het eerste woord als eerste woord van de
-- naam, dan een naam die ermee begint, dan namen waarin meer woorden een woord beginnen, dan nagekeken producten
-- (NEVO), dan de kortste naam.
-- `search_key` is de zoeksleutel van FoodLog.searchKey: kleine letters, zonder accenten. De woorden staan tussen
-- gewone spaties, zoals FoodLog.searchWords ze splitst. Het langste woord gaat via de trigram-index op search_name
-- (schema.sql), want de cache van Open Food Facts groeit; strpos controleert daarna elk woord. Beide nemen elk teken
-- letterlijk: % en _ zijn gewone tekens.
create or replace function public.search_products(search_key text, max_results integer default 30)
returns setof public.products
language sql
stable
set search_path = ''
as $$
  with words as (
    select typed.word, min(typed.position) as position
    from unnest(regexp_split_to_array(search_key, ' +')) with ordinality as typed(word, position)
    where typed.word <> ''
    group by typed.word
  ),
  first_word as (
    select words.word from words order by words.position limit 1
  )
  select products.*
  from public.products
  where products.owner_id is null
    and products.deleted_at is null
    -- Zonder woorden is het patroon null, en vindt dit niets.
    and products.search_name like (
      select '%' || replace(replace(replace(words.word, '\', '\\'), '%', '\%'), '_', '\_') || '%'
      from words order by char_length(words.word) desc, words.word limit 1
    )
    and not exists (select 1 from words where strpos(products.search_name, words.word) = 0)
  order by
    split_part(products.search_name, ' ', 1) = (select first_word.word from first_word) desc,
    starts_with(products.search_name, (select first_word.word from first_word)) desc,
    (select count(*) from words where strpos(' ' || products.search_name, ' ' || words.word) > 0) desc,
    products.is_verified desc,
    char_length(products.search_name),
    products.id
  limit least(greatest(coalesce(max_results, 30), 1), 100);
$$;

revoke execute on function public.search_products(text, integer) from public, anon;
grant execute on function public.search_products(text, integer) to authenticated;

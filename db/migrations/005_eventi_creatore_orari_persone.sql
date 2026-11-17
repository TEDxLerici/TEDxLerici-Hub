-- TEDxLerici HUB · migrazione 005 — pannello evento: creatore, orario di fine, team e persone dedicate
-- Da eseguire UNA VOLTA nel SQL Editor di Supabase (si può rilanciare senza danni).
-- Richiede la 004. Non modifica né cancella dati esistenti.
--   events.by      -> chi ha creato l'evento (solo lui potrà modificarlo)
--   events.h2      -> orario di fine
--   events.teams   -> team coinvolti (vuoto = eventi vecchi: vale il campo team)
--   events.people  -> persone dedicate scelte dall'elenco (id profilo)
--   events.emails  -> indirizzi email aggiunti a mano

do $$
begin
  if to_regclass('public.events') is null then
    raise exception 'Tabella events non trovata.';
  end if;
end $$;

alter table public.events add column if not exists "by"   text;
alter table public.events add column if not exists h2     text;
alter table public.events add column if not exists teams  text[] not null default '{}';
alter table public.events add column if not exists people text[] not null default '{}';
alter table public.events add column if not exists emails text[] not null default '{}';

notify pgrst, 'reload schema';

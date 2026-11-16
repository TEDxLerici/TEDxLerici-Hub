-- TEDxLerici HUB · migrazione 004 — colonne personalizzabili nei fogli + eventi online
-- Da eseguire UNA VOLTA nel SQL Editor di Supabase (si può rilanciare senza danni).
-- Richiede la 003. Non modifica né cancella dati esistenti.
--   1) sheet_cols  -> colonne aggiunte o nascoste nei fogli dei team
--   2) events.mode / events.link -> evento in presenza o online + link della call (usati anche nelle email)

do $$
begin
  if to_regclass('public.sheet_rows') is null then
    raise exception 'Esegui prima la migrazione 003.';
  end if;
end $$;

-- ---------------------------------------------------------------- 1) colonne dei fogli
-- kind = 'add'  : colonna aggiunta (k = c<id>, l = nome, t = tipo, o = opzioni per le tendine)
-- kind = 'hide' : colonna standard rimossa dal foglio (k = chiave della colonna); i dati restano nelle righe
create table if not exists public.sheet_cols (
  id    bigint primary key,
  sheet text not null check (sheet in ('speaker', 'piano', 'insights', 'partner', 'tesoreria', 'eventi', 'inventario')),
  team  text not null check (team in ('MK', 'OP', 'PA', 'SP')),
  kind  text not null check (kind in ('add', 'hide')),
  k     text not null check (length(k) between 1 and 40),
  l     text check (length(l) <= 60),
  t     text check (t in ('text', 'num', 'eur', 'date', 'sel', 'url')),
  o     jsonb not null default '[]'::jsonb,
  check ((sheet, team) in (('speaker', 'SP'), ('piano', 'MK'), ('insights', 'MK'),
                           ('partner', 'PA'), ('tesoreria', 'PA'), ('eventi', 'OP'), ('inventario', 'OP')))
);
create index if not exists sheet_cols_sheet_idx on public.sheet_cols(sheet);

alter table public.sheet_cols enable row level security;

drop policy if exists sheetcols_all on public.sheet_cols;
create policy sheetcols_all on public.sheet_cols for all to authenticated
  using      (public.hub_can_team(team) and (sheet <> 'tesoreria' or public.tes_ok()))
  with check (public.hub_can_team(team) and (sheet <> 'tesoreria' or public.tes_ok()));

grant select, insert, update, delete on public.sheet_cols to authenticated;

-- ---------------------------------------------------------------- 2) eventi in presenza / online
alter table public.events add column if not exists mode text not null default 'presenza';
alter table public.events add column if not exists link text;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'events_mode_check') then
    alter table public.events add constraint events_mode_check check (mode in ('presenza', 'online'));
  end if;
end $$;

notify pgrst, 'reload schema';

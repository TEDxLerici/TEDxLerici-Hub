-- TEDxLerici HUB · migrazione 006 — sezioni personalizzate nei team, segnalazioni (Debug), creatore delle task, data evento main
-- Da eseguire UNA VOLTA nel SQL Editor di Supabase (si può rilanciare senza danni).
-- Richiede la 003/004/005. Non modifica né cancella dati esistenti.
--   1) tasks.by        -> chi ha creato la task (solo lui la modifica; gli altri commentano)
--   2) sheet_defs      -> sezioni (fogli) aggiunte dai team; le righe/colonne usano sheet_rows/sheet_cols
--   3) reports         -> segnalazioni della sezione Debug (tutti scrivono, solo il superadmin risponde/archivia)
--   4) hub_settings    -> impostazioni condivise (data dell'evento principale mostrata in Panoramica)

do $$
begin
  if to_regclass('public.sheet_rows') is null then
    raise exception 'Esegui prima la migrazione 003.';
  end if;
end $$;

create or replace function public.hub_is_sa() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'superadmin')
$$;
create or replace function public.hub_is_lead() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('superadmin', 'lead'))
$$;

-- ---------------------------------------------------------------- 1) creatore delle task
alter table public.tasks add column if not exists "by" text;

-- ---------------------------------------------------------------- 2) sezioni dei team
create table if not exists public.sheet_defs (
  id    bigint primary key,
  team  text not null check (team in ('MK', 'OP', 'PA', 'SP')),
  title text not null check (length(title) between 1 and 80),
  ic    text check (length(ic) <= 8),
  "by"  text
);
alter table public.sheet_defs enable row level security;
drop policy if exists sdef_sel on public.sheet_defs;
drop policy if exists sdef_ins on public.sheet_defs;
drop policy if exists sdef_upd on public.sheet_defs;
drop policy if exists sdef_del on public.sheet_defs;
create policy sdef_sel on public.sheet_defs for select to authenticated using (public.hub_can_team(team));
create policy sdef_ins on public.sheet_defs for insert to authenticated with check (public.hub_can_team(team));
create policy sdef_upd on public.sheet_defs for update to authenticated using (public.hub_can_team(team)) with check (public.hub_can_team(team));
create policy sdef_del on public.sheet_defs for delete to authenticated using (public.hub_is_sa());   -- elimina solo il superadmin
grant select, insert, update, delete on public.sheet_defs to authenticated;

-- righe e colonne dei fogli: ora il nome del foglio può essere anche quello di una sezione nuova (x<id>)
do $$
declare r record;
begin
  for r in select c.conrelid::regclass as t, c.conname
             from pg_constraint c
            where c.contype = 'c'
              and c.conrelid in ('public.sheet_rows'::regclass, 'public.sheet_cols'::regclass)
              and pg_get_constraintdef(c.oid) ilike '%sheet%'
  loop
    execute format('alter table %s drop constraint %I', r.t, r.conname);
  end loop;
end $$;

-- le righe di una sezione possono essere eliminate solo se il foglio è ancora di un team accessibile (RLS già attiva)

-- ---------------------------------------------------------------- 3) segnalazioni (Debug)
create table if not exists public.reports (
  id      bigint primary key,
  "by"    text not null,
  title   text not null check (length(title) between 1 and 160),
  cat     text not null check (cat in ('bug', 'miglioria', 'modifica')),
  body    text not null default '' check (length(body) <= 4000),
  status  text not null default 'aperta' check (status in ('aperta', 'ripristinata')),
  note    text not null default '' check (length(note) <= 4000),
  created text not null default to_char(now(), 'YYYY-MM-DD'),
  done_at text,
  done_by text
);
alter table public.reports enable row level security;
drop policy if exists rep_sel on public.reports;
drop policy if exists rep_ins on public.reports;
drop policy if exists rep_upd on public.reports;
drop policy if exists rep_del on public.reports;
create policy rep_sel on public.reports for select to authenticated using (true);
create policy rep_ins on public.reports for insert to authenticated
  with check ("by" = auth.uid()::text and status = 'aperta' and note = '');
create policy rep_upd on public.reports for update to authenticated using (public.hub_is_sa()) with check (public.hub_is_sa());
create policy rep_del on public.reports for delete to authenticated using (public.hub_is_sa());
grant select, insert, update, delete on public.reports to authenticated;

-- ---------------------------------------------------------------- 4) impostazioni condivise
create table if not exists public.hub_settings (k text primary key, v text not null);
alter table public.hub_settings enable row level security;
drop policy if exists set_sel on public.hub_settings;
drop policy if exists set_ins on public.hub_settings;
drop policy if exists set_upd on public.hub_settings;
create policy set_sel on public.hub_settings for select to authenticated using (true);
create policy set_ins on public.hub_settings for insert to authenticated with check (public.hub_is_lead() and k = 'main_event');
create policy set_upd on public.hub_settings for update to authenticated using (public.hub_is_lead() and k = 'main_event') with check (public.hub_is_lead() and k = 'main_event');
grant select, insert, update on public.hub_settings to authenticated;

notify pgrst, 'reload schema';

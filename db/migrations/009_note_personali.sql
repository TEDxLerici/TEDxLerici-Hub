-- TEDxLerici HUB · migrazione 009 — note personali (solo l'autore) applicabili agli eventi del calendario
-- Da eseguire UNA VOLTA nel SQL Editor di Supabase (si può rilanciare senza danni). Richiede la 006.
--   pnotes: una nota è visibile solo al suo autore finché non viene applicata a un evento (ev);
--           una volta applicata la leggono tutti i membri (non gli ospiti) nella scheda dell'evento.
--           Solo l'autore la scrive, la modifica e la toglie dall'evento; l'autore la elimina; il superadmin può eliminare solo le note già applicate a un evento.
do $$ begin
  if to_regprocedure('public.hub_is_sa()') is null then raise exception 'Esegui prima la migrazione 006.'; end if;
end $$;

create or replace function public.hub_is_member() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles p where p.id = auth.uid() and p.role <> 'guest')
$$;

create table if not exists public.pnotes (
  id   bigint primary key,
  "by" text not null,
  x    text not null check (length(x) between 1 and 4000),
  cat  text not null default 'commento' check (cat in ('commento', 'odg', 'decisione', 'azione')),
  ev   bigint,
  d    text not null default to_char(now(), 'YYYY-MM-DD')
);
alter table public.pnotes enable row level security;
drop policy if exists pn_sel on public.pnotes;
drop policy if exists pn_ins on public.pnotes;
drop policy if exists pn_upd on public.pnotes;
drop policy if exists pn_del on public.pnotes;
create policy pn_sel on public.pnotes for select to authenticated
  using ("by" = auth.uid()::text or (ev is not null and public.hub_is_member()));
create policy pn_ins on public.pnotes for insert to authenticated with check ("by" = auth.uid()::text and public.hub_is_member());
create policy pn_upd on public.pnotes for update to authenticated using ("by" = auth.uid()::text) with check ("by" = auth.uid()::text);
create policy pn_del on public.pnotes for delete to authenticated using ("by" = auth.uid()::text or public.hub_is_sa());
grant select, insert, update, delete on public.pnotes to authenticated;

notify pgrst, 'reload schema';

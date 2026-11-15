-- TEDxLerici HUB · migrazione 003 — aree di lavoro dei team e fogli condivisi
-- Da eseguire UNA VOLTA nel SQL Editor di Supabase (si può rilanciare senza danni).
-- Richiede le migrazioni 001 e 002. Non modifica né cancella dati esistenti.
--   1) profiles.access   -> aree team extra concesse a una persona (oltre al proprio team)
--   2) sheet_rows        -> righe dei fogli (speaker, piano editoriale, insight, partner,
--                           tesoreria, eventi, inventario). Una riga = una persona che modifica.
--   3) tesoreria         -> protetta da password anche lato database (vedi sotto)
--
-- Accesso a un'area team: membri del team, team lead (tutte le aree), superadmin (tutte),
-- più le persone a cui un team lead / superadmin ha concesso l'accesso. Gli ospiti mai.

do $$
begin
  if to_regclass('public.profiles') is null then
    raise exception 'Tabella profiles non trovata: struttura diversa dal previsto, non applico la migrazione.';
  end if;
end $$;

-- ---------------------------------------------------------------- 1) accessi extra
alter table public.profiles add column if not exists access text[] not null default '{}';

create or replace function public.hub_can_team(t text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles p
     where p.id = auth.uid()
       and p.role <> 'guest'
       and (p.role in ('superadmin', 'lead') or p.team = t or t = any (coalesce(p.access, '{}')))
  )
$$;

-- concede / toglie l'accesso a un'area team: superadmin per tutte, team lead solo per il proprio team
create or replace function public.set_team_access(uid text, tm text, allow boolean)
returns void
language plpgsql security definer set search_path = public as $$
declare r text; mine text; tr text;
begin
  select role, team into r, mine from public.profiles where id = auth.uid();
  if r is null then raise exception 'Profilo non trovato.'; end if;
  if tm is null or tm not in ('MK', 'OP', 'PA', 'SP') then raise exception 'Team non valido.'; end if;
  if r <> 'superadmin' and not (r = 'lead' and mine = tm) then
    raise exception 'Solo il team lead del team o il superadmin possono gestire questo accesso.';
  end if;
  select role into tr from public.profiles where id::text = uid;
  if tr is null then raise exception 'Utente non trovato.'; end if;
  if tr = 'guest' then raise exception 'Gli ospiti non possono avere accesso alle aree team.'; end if;
  update public.profiles
     set access = case when allow
                       then (select coalesce(array_agg(distinct x), '{}') from unnest(coalesce(access, '{}') || tm) x)
                       else array_remove(coalesce(access, '{}'), tm) end
   where id::text = uid;
end $$;

revoke all on function public.set_team_access(text, text, boolean) from public, anon;
grant execute on function public.set_team_access(text, text, boolean) to authenticated;

-- ---------------------------------------------------------------- 2) righe dei fogli
create table if not exists public.sheet_rows (
  id    bigint primary key,
  sheet text not null check (sheet in ('speaker', 'piano', 'insights', 'partner', 'tesoreria', 'eventi', 'inventario')),
  team  text not null check (team in ('MK', 'OP', 'PA', 'SP')),
  d     jsonb not null default '{}'::jsonb,
  check ((sheet, team) in (('speaker', 'SP'), ('piano', 'MK'), ('insights', 'MK'),
                           ('partner', 'PA'), ('tesoreria', 'PA'), ('eventi', 'OP'), ('inventario', 'OP')))
);
create index if not exists sheet_rows_sheet_idx on public.sheet_rows(sheet);

-- ---------------------------------------------------------------- 3) password tesoreria
-- La password non è scritta qui: è salvata come impronta (hash) in una tabella che nessun utente può leggere.
create table if not exists public.hub_secrets (k text primary key, v text not null);
alter table public.hub_secrets enable row level security;      -- nessuna policy: solo le funzioni sotto la leggono
revoke all on public.hub_secrets from anon, authenticated;

insert into public.hub_secrets(k, v)
values ('tes_pw', 'ca52a2019a40179a0b6ab3fe25ab779825eedff5b12089ce354db8690b407032')
on conflict (k) do nothing;

create table if not exists public.tes_unlock (uid uuid primary key, until timestamptz not null);
alter table public.tes_unlock enable row level security;
revoke all on public.tes_unlock from anon, authenticated;

create or replace function public.tes_ok() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.tes_unlock where uid = auth.uid() and until > now())
$$;

create or replace function public.tes_status() returns boolean
language sql stable security definer set search_path = public as $$ select public.tes_ok() $$;

-- sblocca la tesoreria per 8 ore, se la password è giusta e la persona ha accesso all'area Partner
create or replace function public.tes_unlock(pw text) returns boolean
language plpgsql security definer set search_path = public as $$
declare h text;
begin
  if auth.uid() is null or not public.hub_can_team('PA') then return false; end if;
  select v into h from public.hub_secrets where k = 'tes_pw';
  if h is not null and h = encode(sha256(convert_to('hub-tes:' || coalesce(pw, ''), 'UTF8')), 'hex') then
    insert into public.tes_unlock(uid, until) values (auth.uid(), now() + interval '8 hours')
    on conflict (uid) do update set until = excluded.until;
    return true;
  end if;
  perform pg_sleep(1);                                          -- rallenta i tentativi a vuoto
  return false;
end $$;

create or replace function public.tes_lock() returns void
language sql security definer set search_path = public as $$
  delete from public.tes_unlock where uid = auth.uid()
$$;

-- solo il superadmin cambia la password:  select public.tes_set_password('NuovaPassword');
create or replace function public.tes_set_password(new_pw text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if coalesce((select role from public.profiles where id = auth.uid()), '') <> 'superadmin' then
    raise exception 'Solo il superadmin può cambiare la password della tesoreria.';
  end if;
  if length(coalesce(new_pw, '')) < 8 then raise exception 'Minimo 8 caratteri.'; end if;
  insert into public.hub_secrets(k, v)
  values ('tes_pw', encode(sha256(convert_to('hub-tes:' || new_pw, 'UTF8')), 'hex'))
  on conflict (k) do update set v = excluded.v;
  delete from public.tes_unlock;                                 -- tutti devono reinserire la nuova password
end $$;

revoke all on function public.tes_status() from public, anon;
revoke all on function public.tes_unlock(text) from public, anon;
revoke all on function public.tes_lock() from public, anon;
revoke all on function public.tes_set_password(text) from public, anon;
grant execute on function public.tes_status() to authenticated;
grant execute on function public.tes_unlock(text) to authenticated;
grant execute on function public.tes_lock() to authenticated;
grant execute on function public.tes_set_password(text) to authenticated;

-- ---------------------------------------------------------------- sicurezza righe (RLS)
alter table public.sheet_rows enable row level security;

drop policy if exists sheet_all on public.sheet_rows;
create policy sheet_all on public.sheet_rows for all to authenticated
  using      (public.hub_can_team(team) and (sheet <> 'tesoreria' or public.tes_ok()))
  with check (public.hub_can_team(team) and (sheet <> 'tesoreria' or public.tes_ok()));

grant select, insert, update, delete on public.sheet_rows to authenticated;

notify pgrst, 'reload schema';

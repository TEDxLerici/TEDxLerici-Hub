-- TEDxLerici HUB · migrazione 002
-- Da eseguire UNA VOLTA nel SQL Editor di Supabase (si può rilanciare senza danni).
-- Se non la esegui l'app continua a funzionare, ma queste funzioni restano spente:
--   1) tasks.num        -> ID progressivo della task (#001, #002, ...)
--   2) profili          -> nome, cognome, telefono, foto + scelta del team di riferimento
--   3) meetings.minutes -> appunti delle riunioni
--   4) suggestions      -> task suggerite dagli appunti, da approvare (team lead / superadmin)
-- Non modifica né cancella dati esistenti.

do $$
begin
  if to_regclass('public.tasks') is null or to_regclass('public.profiles') is null or to_regclass('public.meetings') is null then
    raise exception 'Tabelle tasks, profiles o meetings non trovate: la struttura è diversa dal previsto, non applico la migrazione.';
  end if;
end $$;

-- ---------------------------------------------------------------- 1) ID task
create sequence if not exists public.tasks_num_seq;
alter table public.tasks add column if not exists num integer;

-- numera le task già esistenti in ordine di creazione (id)
with ord as (select id, row_number() over (order by id) as rn from public.tasks where num is null),
     mx  as (select coalesce(max(num), 0) as m from public.tasks)
update public.tasks t set num = ord.rn + mx.m from ord, mx where t.id = ord.id;

do $$
declare m int;
begin
  select coalesce(max(num), 0) into m from public.tasks;
  perform setval('public.tasks_num_seq', greatest(m, 1), m > 0);
end $$;

create unique index if not exists tasks_num_key on public.tasks(num);

-- il numero lo assegna il database all'inserimento e non cambia più
create or replace function public.tasks_set_num() returns trigger
language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    if new.num is null then new.num := nextval('public.tasks_num_seq'); end if;
  else
    new.num := old.num;
  end if;
  return new;
end $$;

drop trigger if exists tasks_set_num on public.tasks;
create trigger tasks_set_num before insert or update on public.tasks
  for each row execute function public.tasks_set_num();

-- ---------------------------------------------------------------- 2) profili
alter table public.profiles
  add column if not exists first_name text,
  add column if not exists last_name  text,
  add column if not exists phone      text,
  add column if not exists photo      text;

-- ognuno modifica solo il proprio profilo (nome, telefono, foto); ruolo e team non si toccano da qui
create or replace function public.update_my_profile(p_first text, p_last text, p_phone text, p_photo text, p_set_photo boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  full_name text;
  gen text;
begin
  if auth.uid() is null then raise exception 'Devi essere autenticato.'; end if;
  p_first := left(trim(coalesce(p_first, '')), 60);
  p_last  := left(trim(coalesce(p_last, '')), 60);
  p_phone := left(trim(coalesce(p_phone, '')), 30);
  if p_first = '' then raise exception 'Il nome è obbligatorio.'; end if;
  if p_phone <> '' and p_phone !~ '^[0-9+ ()./-]{6,30}$' then raise exception 'Telefono non valido.'; end if;
  if p_set_photo and coalesce(p_photo, '') <> '' then
    if p_photo !~ '^data:image/(jpeg|png|webp);base64,' or length(p_photo) > 250000 then
      raise exception 'Foto non valida o troppo grande.';
    end if;
  end if;

  full_name := trim(p_first || ' ' || p_last);
  update public.profiles
     set first_name = p_first, last_name = p_last, phone = nullif(p_phone, ''), name = full_name
   where id = auth.uid();
  if p_set_photo then
    update public.profiles set photo = nullif(p_photo, '') where id = auth.uid();
  end if;

  -- iniziali: solo se la colonna esiste ed è scrivibile
  select is_generated into gen from information_schema.columns
   where table_schema = 'public' and table_name = 'profiles' and column_name = 'ini';
  if found and gen = 'NEVER' then
    execute 'update public.profiles set ini = $1 where id = auth.uid()'
      using upper(left(p_first, 1) || left(p_last, 1));
  end if;
end $$;

-- team di riferimento: chi non ne ha ancora uno può sceglierlo; poi lo cambia solo il superadmin
-- (o il team lead / superadmin dalla pagina Team, come prima)
create or replace function public.set_my_team(tm text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare r text; cur text;
begin
  select role, team into r, cur from public.profiles where id = auth.uid();
  if r is null then raise exception 'Profilo non trovato.'; end if;
  if tm is not null and tm not in ('MK', 'OP', 'PA', 'SP') then raise exception 'Team non valido.'; end if;
  if r = 'guest' then raise exception 'Gli ospiti non appartengono a un team.'; end if;
  if r <> 'superadmin' and cur is not null then
    raise exception 'Per cambiare team chiedi al team lead o al superadmin.';
  end if;
  if r <> 'superadmin' and tm is null then raise exception 'Scegli un team.'; end if;
  update public.profiles set team = tm where id = auth.uid();
end $$;

revoke all on function public.update_my_profile(text, text, text, text, boolean) from public, anon;
revoke all on function public.set_my_team(text) from public, anon;
grant execute on function public.update_my_profile(text, text, text, text, boolean) to authenticated;
grant execute on function public.set_my_team(text) to authenticated;

-- ---------------------------------------------------------------- 3) appunti riunione
alter table public.meetings add column if not exists minutes text not null default '';

-- ---------------------------------------------------------------- 4) task suggerite
create or replace function public.hub_role() returns text
language sql stable security definer set search_path = public as
$$ select role from public.profiles where id = auth.uid() $$;

create or replace function public.hub_team() returns text
language sql stable security definer set search_path = public as
$$ select team from public.profiles where id = auth.uid() $$;

create table if not exists public.suggestions (
  id          bigint primary key,
  meeting     bigint references public.meetings(id) on delete cascade,
  title       text not null check (length(title) between 1 and 160),
  team        text check (team in ('MK', 'OP', 'PA', 'SP')),
  own         text,
  asg         text[] not null default '{}',
  s           date,
  e           date,
  why         text,
  status      text not null default 'pending' check (status in ('pending', 'accepted', 'dismissed')),
  by          text,
  task_id     bigint references public.tasks(id) on delete set null,
  decided_by  text,
  created_at  timestamptz not null default now()
);
create index if not exists suggestions_meeting_idx on public.suggestions(meeting);

alter table public.suggestions enable row level security;

drop policy if exists sug_select on public.suggestions;
create policy sug_select on public.suggestions for select to authenticated
  using (coalesce(public.hub_role(), 'guest') <> 'guest');

-- chiunque non sia ospite può proporre, ma solo come "in attesa"
drop policy if exists sug_insert on public.suggestions;
create policy sug_insert on public.suggestions for insert to authenticated
  with check (coalesce(public.hub_role(), 'guest') <> 'guest' and status = 'pending' and by = auth.uid()::text);

-- accettare / scartare: superadmin, oppure team lead del team indicato
drop policy if exists sug_update on public.suggestions;
create policy sug_update on public.suggestions for update to authenticated
  using (public.hub_role() = 'superadmin' or (public.hub_role() = 'lead' and team is not null and team = public.hub_team()))
  with check (public.hub_role() = 'superadmin' or (public.hub_role() = 'lead' and team is not null and team = public.hub_team()));

drop policy if exists sug_delete on public.suggestions;
create policy sug_delete on public.suggestions for delete to authenticated
  using (public.hub_role() = 'superadmin'
         or (public.hub_role() = 'lead' and team is not null and team = public.hub_team())
         or (by = auth.uid()::text and status = 'pending'));

grant select, insert, update, delete on public.suggestions to authenticated;

-- fa rileggere subito lo schema all'API
notify pgrst, 'reload schema';

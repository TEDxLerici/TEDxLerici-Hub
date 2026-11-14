-- TEDxLerici HUB · migrazione 001
-- Da eseguire UNA VOLTA nel SQL Editor di Supabase, PRIMA di mettere online la nuova versione dell'app.
-- Contenuto:
--   1) tasks.asg      -> altre persone coinvolte in una task (l'owner resta in tasks.own)
--   2) edit_comment   -> modifica un commento (solo l'autore)
--   3) delete_comment -> elimina un commento (autore o superadmin)
-- Non tocca la colonna tasks.p (avanzamento): l'app non la usa più ma i dati restano.

-- Controllo di sicurezza: i commenti devono stare in tasks.c come jsonb
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'tasks'
      and column_name = 'c' and data_type = 'jsonb'
  ) then
    raise exception 'tasks.c non è una colonna jsonb: la struttura dei commenti è diversa dal previsto, non applico la migrazione.';
  end if;
end $$;

-- 1) Altre persone coinvolte (id utente come testo, l'owner non va ripetuto qui)
alter table public.tasks
  add column if not exists asg text[] not null default '{}';

-- 2) Modifica commento: l'indice identifica il commento, il testo precedente
--    protegge da modifiche concorrenti (se nel frattempo è cambiato, rifiuta).
create or replace function public.edit_comment(tid bigint, idx int, old_txt text, new_txt text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  cur jsonb;
begin
  if auth.uid() is null then
    raise exception 'Devi essere autenticato.';
  end if;
  if new_txt is null or length(trim(new_txt)) = 0 then
    raise exception 'Il commento non può essere vuoto.';
  end if;

  select c into cur from public.tasks where id = tid for update;
  if cur is null or idx < 0 or idx >= jsonb_array_length(cur) then
    raise exception 'Commento non trovato.';
  end if;
  if (cur -> idx ->> 'u') is distinct from auth.uid()::text then
    raise exception 'Puoi modificare solo i tuoi commenti.';
  end if;
  if (cur -> idx ->> 'x') is distinct from old_txt then
    raise exception 'Il commento è cambiato nel frattempo: ricarica e riprova.';
  end if;

  update public.tasks
     set c = jsonb_set(cur, array[idx::text], (cur -> idx) || jsonb_build_object('x', trim(new_txt), 'edited', true))
   where id = tid;
end $$;

-- 3) Elimina commento: autore oppure superadmin
create or replace function public.delete_comment(tid bigint, idx int, old_txt text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  cur jsonb;
  is_admin boolean;
begin
  if auth.uid() is null then
    raise exception 'Devi essere autenticato.';
  end if;

  select c into cur from public.tasks where id = tid for update;
  if cur is null or idx < 0 or idx >= jsonb_array_length(cur) then
    raise exception 'Commento non trovato.';
  end if;

  select exists (select 1 from public.profiles where id = auth.uid() and role = 'superadmin') into is_admin;
  if not is_admin and (cur -> idx ->> 'u') is distinct from auth.uid()::text then
    raise exception 'Puoi eliminare solo i tuoi commenti.';
  end if;
  if (cur -> idx ->> 'x') is distinct from old_txt then
    raise exception 'Il commento è cambiato nel frattempo: ricarica e riprova.';
  end if;

  update public.tasks
     set c = coalesce(
           (select jsonb_agg(e order by ord)
              from jsonb_array_elements(cur) with ordinality as t(e, ord)
             where ord - 1 <> idx),
           '[]'::jsonb)
   where id = tid;
end $$;

revoke all on function public.edit_comment(bigint, int, text, text) from public, anon;
revoke all on function public.delete_comment(bigint, int, text) from public, anon;
grant execute on function public.edit_comment(bigint, int, text, text) to authenticated;
grant execute on function public.delete_comment(bigint, int, text) to authenticated;

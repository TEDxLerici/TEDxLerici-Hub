-- TEDxLerici HUB · migrazione 007 — correzione Debug: il superadmin può archiviare / completare le segnalazioni
-- Da eseguire UNA VOLTA nel SQL Editor di Supabase (si può rilanciare senza danni). Richiede la 006.
-- Problema: l'app salva le modifiche con "upsert" (INSERT … ON CONFLICT DO UPDATE) e Postgres applica anche la regola
-- di inserimento alla riga nuova: una segnalazione con note o stato «completata» veniva rifiutata, anche se il
-- superadmin ha il permesso di modificarla. Ora il superadmin passa anche dalla regola di inserimento.

do $$
begin
  if to_regclass('public.reports') is null then
    raise exception 'Esegui prima la migrazione 006.';
  end if;
end $$;

drop policy if exists rep_ins on public.reports;
create policy rep_ins on public.reports for insert to authenticated
  with check (public.hub_is_sa() or ("by" = auth.uid()::text and status = 'aperta' and note = ''));

notify pgrst, 'reload schema';

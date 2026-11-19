-- 008 · La data del TEDx Main Event (Panoramica) può essere modificata solo dal superadmin.
-- Richiede la migrazione 006 (tabella hub_settings e funzione hub_is_sa).
drop policy if exists set_ins on public.hub_settings;
drop policy if exists set_upd on public.hub_settings;
create policy set_ins on public.hub_settings for insert to authenticated with check (public.hub_is_sa() and k = 'main_event');
create policy set_upd on public.hub_settings for update to authenticated using (public.hub_is_sa() and k = 'main_event') with check (public.hub_is_sa() and k = 'main_event');
notify pgrst, 'reload schema';

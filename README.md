# TEDxLerici-Hub
## Database (Supabase)

Gli script SQL sono in `db/migrations/` e vanno eseguiti **una volta**, in ordine, nel SQL Editor di Supabase **prima** di pubblicare la versione dell'app che li usa:

1. `001_assegnatari_e_commenti.sql` — più persone per task, modifica/eliminazione commenti
2. `002_id_task_profilo_appunti_suggerimenti.sql` — ID task (#001), profilo personale, appunti riunione, task suggerite da approvare
3. `003_aree_team_e_fogli.sql` — aree di lavoro dei team, fogli condivisi, accessi extra, tesoreria con password (cambiabile dal superadmin con `select public.tes_set_password('NuovaPassword');`)

Si possono rilanciare senza danni. Senza la 002 / 003 l'app funziona comunque, ma le nuove funzioni restano spente.

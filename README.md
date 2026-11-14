# TEDxLerici-Hub
## Database (Supabase)

Gli script SQL sono in `db/migrations/` e vanno eseguiti **una volta**, in ordine, nel SQL Editor di Supabase **prima** di pubblicare la versione dell'app che li usa:

1. `001_assegnatari_e_commenti.sql` — più persone per task, modifica/eliminazione commenti
2. `002_id_task_profilo_appunti_suggerimenti.sql` — ID task (#001), profilo personale, appunti riunione, task suggerite da approvare

Si possono rilanciare senza danni. Senza la 002 l'app funziona comunque, ma le nuove funzioni restano spente.

# TEDxLerici-Hub
## Database (Supabase)

Gli script SQL sono in `db/migrations/` e vanno eseguiti **una volta**, in ordine, nel SQL Editor di Supabase **prima** di pubblicare la versione dell'app che li usa:

1. `001_assegnatari_e_commenti.sql` — più persone per task, modifica/eliminazione commenti
2. `002_id_task_profilo_appunti_suggerimenti.sql` — ID task (#001), profilo personale, appunti riunione, task suggerite da approvare
3. `003_aree_team_e_fogli.sql` — aree di lavoro dei team, fogli condivisi, accessi extra, tesoreria con password (cambiabile dal superadmin con `select public.tes_set_password('NuovaPassword');`)
4. `004_colonne_fogli_e_eventi_online.sql` — colonne aggiunte/rimosse nei fogli, eventi in presenza/online con link della call

Si possono rilanciare senza danni. Senza la 002 / 003 l'app funziona comunque, ma le nuove funzioni restano spente.

## Email automatiche per i nuovi eventi

Quando si crea un evento (o un meeting) l'app chiama `api/send-event.js`, che invia una email con titolo, data, ora, luogo
(in presenza / online con link della call) e descrizione, più un invito `.ics` per il calendario.
Destinatari: persone del team dell'evento (o tutta la crew) e superadmin; mai gli ospiti né chi crea l'evento.
Li ricava il server dal database: dal browser non si possono inserire indirizzi.

Su Vercel, *Project → Settings → Environment Variables* (poi *Redeploy*):

| Variabile | Valore |
|---|---|
| `RESEND_API_KEY` | chiave API di [Resend](https://resend.com) |
| `MAIL_FROM` | mittente, es. `TEDxLerici HUB <hub@tuodominio.it>` (dominio verificato su Resend) |

Senza queste variabili l'evento viene salvato normalmente e l'app avvisa che l'email non è configurata.

# TEDxLerici-Hub
## Database (Supabase)

Gli script SQL sono in `db/migrations/` e vanno eseguiti **una volta**, in ordine, nel SQL Editor di Supabase **prima** di pubblicare la versione dell'app che li usa:

1. `001_assegnatari_e_commenti.sql` — più persone per task, modifica/eliminazione commenti
2. `002_id_task_profilo_appunti_suggerimenti.sql` — ID task (#001), profilo personale, appunti riunione, task suggerite da approvare
3. `003_aree_team_e_fogli.sql` — aree di lavoro dei team, fogli condivisi, accessi extra, tesoreria con password (cambiabile dal superadmin con `select public.tes_set_password('NuovaPassword');`)
4. `004_colonne_fogli_e_eventi_online.sql` — colonne aggiunte/rimosse nei fogli, eventi in presenza/online con link della call
5. `005_eventi_creatore_orari_persone.sql` — chi ha creato l'evento, orario di fine, team coinvolti, persone dedicate e email aggiunte a mano
6. `006_sezioni_segnalazioni_task.sql` — sezioni aggiunte dai team (eliminabili solo dal superadmin), segnalazioni della pagina Debug, creatore delle task, data dell'evento principale

Si possono rilanciare senza danni. Senza la 002 / 003 l'app funziona comunque, ma le nuove funzioni restano spente.

## Email automatiche per i nuovi eventi

Quando si crea un evento (o un meeting) l'app chiama `api/send-event.js`, che invia una email con titolo, data, ora, luogo
(in presenza / online con link della call) e descrizione, più un invito `.ics` per il calendario.
Destinatari: se l'evento è per "Tutta la crew" tutte le persone dei 4 team; se è per un team (o per i team di un meeting) solo le persone di quel team. Chi non ha un team e gli ospiti non ricevono nulla. Le persone senza email nel profilo vengono segnalate all'organizzatore. L'invito e il file `.ics` riportano chi ha creato l'evento (note e organizzatore del calendario). Chi crea l'evento non riceve l'invito ma, sempre, un promemoria a parte con i dettagli e l'elenco di chi è stato invitato.
Li ricava il server dal database: dal browser si mandano solo gli id dei team e delle persone scelte (più, a mano, al massimo 10 indirizzi email validati).

**Pannello evento** (richiede la migrazione 005): l'evento ha titolo, data, orario di inizio e fine, modalità e luogo (link se online), team coinvolti (singoli team o "Tutta la crew"), eventuali persone dedicate (dall'elenco o con email a mano) e descrizione. Alla creazione la email parte in automatico. Solo chi ha creato l'evento può modificarlo (matita ✎ nella scheda): se cambia qualcosa compare la spunta «Avvisa di nuovo» e, se non è spuntata, l'app chiede se avvisare comunque; l'email di aggiornamento elenca cosa è cambiato e l'invito `.ics` aggiorna lo stesso evento nel calendario. Senza la 005 l'app funziona come prima (modifica ai team lead del team e al superadmin).

Su Vercel, *Project → Settings → Environment Variables* (poi *Redeploy*):

| Variabile | Valore |
|---|---|
| `RESEND_API_KEY` | chiave API di [Resend](https://resend.com) |
| `MAIL_FROM` | mittente, es. `TEDxLerici HUB <hub@tuodominio.it>` (dominio verificato su Resend) |

Senza queste variabili l'evento viene salvato normalmente e l'app avvisa che l'email non è configurata.

## Novità di interfaccia (richiedono la migrazione 006)

- **Fogli**: il `+` in fondo alle colonne aggiunge una colonna, la `×` sull'intestazione la toglie, la barra «+ Aggiungi riga» sotto la tabella aggiunge una riga e il cestino compare passando sulla riga (con «Annulla» per 7 secondi).
- **Sezioni dei team**: «+ Nuova sezione» nelle schede del team crea un foglio nuovo (Voce, Stato, Responsabile, Scadenza, Note) che si può rinominare; solo il superadmin può eliminarlo.
- **Task**: aprendo una task si vede la scheda; solo chi l'ha creata può modificarla (matita ✎), gli altri commentano. Le task vecchie senza creatore seguono le regole di prima.
- **Debug**: tutti possono fare una segnalazione (titolo, categoria, dettagli); il superadmin scrive le note e con «✓ Ripristinata» la manda nell'Archivio.
- **Panoramica**: la data del TEDx Main Event si cambia con la matita (team lead e superadmin).
- La sezione File non è più nel menu (i dati restano nel database).

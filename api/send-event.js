// TEDxLerici HUB · invio email per un nuovo evento (Vercel Serverless Function)
//
// Variabili d'ambiente su Vercel (Project → Settings → Environment Variables):
//   RESEND_API_KEY   chiave del servizio email Resend (https://resend.com)
//   MAIL_FROM        mittente, es.  TEDxLerici HUB <hub@tuodominio.it>   (dominio verificato su Resend)
//   SUPABASE_URL, SUPABASE_ANON_KEY   (opzionali: se mancano si usano quelli pubblici del sito)
//
// Sicurezza: la funzione NON accetta indirizzi email dal browser. Verifica chi chiama con il suo token Supabase,
// controlla che sia team lead o superadmin e ricava i destinatari dai profili nel database
// (tutta la crew = persone dei 4 team; un team = solo le persone di quel team).

const SB_URL = process.env.SUPABASE_URL || 'https://qugfxkymtnfnkdasmwgt.supabase.co';
const SB_KEY = process.env.SUPABASE_ANON_KEY || 'sb_publishable_g3Exxy0sebxbGIutdHrPZQ_7LBnHM-9';
const TEAMS = { MK: 'Marketing', OP: 'Operations', PA: 'Partner', SP: 'Speaker' };

const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const okDate = s => /^\d{4}-\d{2}-\d{2}$/.test(s) && !isNaN(new Date(s + 'T00:00:00Z'));
const okTime = s => /^\d{2}:\d{2}$/.test(s);
const okUrl = s => /^https?:\/\/[^\s<>"']+$/i.test(s);

function longDate(d) {
  const s = new Intl.DateTimeFormat('it-IT', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' }).format(new Date(d + 'T12:00:00Z'));
  return s.charAt(0).toUpperCase() + s.slice(1);
}

function buildEmail(ev, who, opt = {}) {
  const online = ev.mode === 'online';
  const place = online ? 'Online' + (ev.where ? ' · ' + ev.where : '') : (ev.where || 'Da definire') + ' (in presenza)';
  const rows = [['Quando', longDate(ev.d) + (ev.h ? ' · ore ' + ev.h : '')], ['Dove', place]];
  if (online && ev.link) rows.push(['Link della call', ev.link]);
  if (ev.creator) rows.push(['Creato da', ev.creator]);
  const row = ([k, v]) => `<tr><td style="padding:8px 14px 8px 0;color:#777;font-size:13px;vertical-align:top;white-space:nowrap">${k}</td><td style="padding:8px 0;font-size:15px;color:#111">${k === 'Link della call' ? `<a href="${esc(v)}" style="color:#e62b1e;font-weight:700">${esc(v)}</a>` : esc(v)}</td></tr>`;
  const html = `<div style="font-family:Helvetica,Arial,sans-serif;max-width:560px;margin:0 auto;padding:24px;color:#111">
<div style="font-size:12px;letter-spacing:.14em;color:#e62b1e;font-weight:700">TEDXLERICI HUB · ${opt.reminder ? 'PROMEMORIA · EVENTO CREATO' : 'NUOVO EVENTO'}</div>
<h1 style="font-size:24px;margin:8px 0 16px">${esc(ev.t)}</h1>
<table style="border-collapse:collapse;width:100%;border-top:1px solid #eee;border-bottom:1px solid #eee">${rows.map(row).join('')}</table>
${ev.desc ? `<p style="font-size:15px;line-height:1.55;margin:18px 0;white-space:pre-line">${esc(ev.desc)}</p>` : ''}
${online && ev.link ? `<p><a href="${esc(ev.link)}" style="display:inline-block;background:#e62b1e;color:#fff;padding:11px 20px;border-radius:8px;text-decoration:none;font-weight:700">Apri la call</a></p>` : ''}
${opt.reminder ? `<div style="background:#f6f6f6;border-radius:10px;padding:12px 14px;font-size:13px;line-height:1.5;margin-top:18px"><b>Invito inviato a ${opt.invited.length} ${opt.invited.length === 1 ? 'persona' : 'persone'}</b>${opt.invited.length ? ': ' + esc(opt.invited.join(', ')) : ''}${opt.failed ? `<br>Non consegnato a ${opt.failed} ${opt.failed === 1 ? 'persona' : 'persone'}.` : ''}${opt.noMail && opt.noMail.length ? `<br>Senza email nel profilo: ${esc(opt.noMail.join(', '))}.` : ''}</div>` : ''}
<p style="font-size:12px;color:#999;margin-top:26px">${opt.reminder ? `Ciao ${esc(who)}, questo è il promemoria dell'evento che hai creato nel calendario (per ${ev.teamName ? 'il team ' + esc(ev.teamName) : 'tutta la crew'}). In allegato trovi l'invito da aggiungere al tuo calendario.` : `Ciao ${esc(who)}, ricevi questa email perché l'evento riguarda ${ev.teamName ? 'il team ' + esc(ev.teamName) : 'tutta la crew'}. In allegato trovi l'invito da aggiungere al calendario.`}</p></div>`;
  const text = [`${opt.reminder ? 'PROMEMORIA · EVENTO CREATO' : 'NUOVO EVENTO'} · ${ev.t}`, '', ...rows.map(([k, v]) => `${k}: ${v}`), ev.desc ? '\n' + ev.desc : '',
    opt.reminder ? `\nInvito inviato a ${opt.invited.length} persone${opt.invited.length ? ': ' + opt.invited.join(', ') : ''}${opt.failed ? ` (non consegnato a ${opt.failed})` : ''}.` : ''].join('\n');
  return { html, text };
}

function ics(ev) {
  const z = s => s.replace(/[-:]/g, '');
  const start = z(ev.d) + 'T' + z(ev.h || '09:00') + '00';
  const fold = s => String(s).replace(/\\/g, '\\\\').replace(/;/g, '\\;').replace(/,/g, '\\,').replace(/\r?\n/g, '\\n');
  const loc = ev.mode === 'online' ? (ev.link || 'Online') : (ev.where || '');
  return ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//TEDxLerici HUB//IT', 'METHOD:PUBLISH', 'BEGIN:VEVENT',
    `UID:${Date.now()}-${Math.random().toString(36).slice(2)}@tedxlerici-hub`, `DTSTAMP:${new Date().toISOString().replace(/[-:]|\.\d+/g, '')}`,
    `DTSTART:${start}`, `SUMMARY:${fold(ev.t)}`, `LOCATION:${fold(loc)}`,
    ...(ev.creator && ev.creatorEmail ? [`ORGANIZER;CN=${fold(ev.creator)}:mailto:${ev.creatorEmail}`] : []),
    `DESCRIPTION:${fold((ev.desc || '') + (ev.mode === 'online' && ev.link ? '\nLink della call: ' + ev.link : '') + (ev.creator ? '\nCreato da: ' + ev.creator : ''))}`,
    'END:VEVENT', 'END:VCALENDAR'].join('\r\n');
}

// Controllo di configurazione: apri /api/send-event?check. Non mostra mai la chiave e non invia email reali
// (la prova usa l'indirizzo di test delivered@resend.dev di Resend).
async function diagnose(res) {
  const key = process.env.RESEND_API_KEY || '', from = process.env.MAIL_FROM || '';
  const out = {
    RESEND_API_KEY: !key ? 'MANCANTE' : { lunghezza: key.length, iniziaCon_re_: key.startsWith('re_'),
      spaziOVirgoletteNelValore: /\s|["']/.test(key), formatoPlausibile: /^re_[A-Za-z0-9_]{20,}$/.test(key) },
    MAIL_FROM: from || 'MANCANTE',
    formatoMailFrom: /^[^<>]+<[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+>$|^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(from.trim()) ? 'ok' : 'non valido',
  };
  if (key && from) {
    try {
      const r = await fetch('https://api.resend.com/emails', { method: 'POST', headers: { Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' },
        body: JSON.stringify({ from, to: ['delivered@resend.dev'], subject: 'Prova configurazione TEDxLerici HUB', text: 'Prova' }) });
      let j = {}; try { j = await r.json() } catch (e) {}
      out.resend = { stato: r.status, esito: r.ok ? 'chiave e mittente accettati' : (j.message || j.name || 'rifiutato') };
    } catch (e) { out.resend = { errore: e.message } }
  }
  return res.status(200).json(out);
}

module.exports = async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  if (req.method === 'GET' && /[?&]check(=|&|$)/.test(req.url || '')) return diagnose(res);
  if (req.method !== 'POST') return res.status(405).json({ error: 'Metodo non consentito' });
  const apiKey = process.env.RESEND_API_KEY, from = process.env.MAIL_FROM;
  if (!apiKey || !from) return res.status(501).json({ error: 'Invio email non configurato' });

  const token = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
  if (!token) return res.status(401).json({ error: 'Non autenticato' });
  const sb = (path) => fetch(SB_URL + path, { headers: { apikey: SB_KEY, Authorization: 'Bearer ' + token } });

  const ur = await sb('/auth/v1/user');
  if (!ur.ok) return res.status(401).json({ error: 'Sessione non valida' });
  const uid = (await ur.json()).id;
  const pr = await sb('/rest/v1/profiles?select=id,name,email,role,team');
  if (!pr.ok) return res.status(502).json({ error: 'Impossibile leggere i profili' });
  const profiles = await pr.json();
  const me = profiles.find(p => p.id === uid);
  if (!me || !['lead', 'superadmin'].includes(me.role)) return res.status(403).json({ error: 'Solo team lead e superadmin possono inviare inviti' });

  let body = req.body;
  if (typeof body === 'string') { try { body = JSON.parse(body) } catch (e) { body = null } }
  const ev = body && body.event;
  if (!ev || typeof ev.t !== 'string' || !ev.t.trim() || ev.t.length > 160) return res.status(400).json({ error: 'Titolo mancante o troppo lungo' });
  if (!okDate(ev.d)) return res.status(400).json({ error: 'Data non valida' });
  if (ev.h && !okTime(ev.h)) return res.status(400).json({ error: 'Ora non valida' });
  if (ev.mode === 'online' && !okUrl(ev.link || '')) return res.status(400).json({ error: 'Evento online senza link valido' });
  ev.mode = ev.mode === 'online' ? 'online' : 'presenza';
  ev.where = String(ev.where || '').slice(0, 200); ev.desc = String(ev.desc || '').slice(0, 3000);
  if (ev.mode !== 'online') ev.link = '';

  const teams = (Array.isArray(body.teams) ? body.teams : []).filter(t => TEAMS[t]);
  if (me.role === 'lead' && teams.some(t => t !== me.team)) return res.status(403).json({ error: 'Un team lead può invitare solo il proprio team o tutta la crew' });
  ev.teamName = teams.length === 1 ? TEAMS[teams[0]] : '';

  // Destinatari, ricavati dal database:
  //  - tutta la crew (nessun team indicato) -> tutte le persone dei 4 team;
  //  - uno o più team -> solo le persone di quei team.
  // Chi non ha un team e gli ospiti non ricevono nulla.
  // Chi crea l'evento non riceve l'invito ma un PROMEMORIA a parte (con l'elenco di chi è stato invitato), sempre.
  const validMail = m => typeof m === 'string' && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(m.trim());
  const scope = profiles.filter(p => p.id !== uid && p.role !== 'guest' && TEAMS[p.team] && (!teams.length || teams.includes(p.team)));
  const to = scope.filter(p => validMail(p.email)).slice(0, 80);
  const senzaEmail = scope.filter(p => !validMail(p.email)).map(p => p.name || 'Senza nome');
  ev.creator = me.name || '';
  ev.creatorEmail = validMail(me.email) ? me.email.trim() : '';

  const attach = [{ filename: 'invito.ics', content: Buffer.from(ics(ev), 'utf8').toString('base64') }];
  const when = `${longDate(ev.d).replace(/^\S+\s/, '')}${ev.h ? ' ore ' + ev.h : ''}`;
  const subject = `Nuovo evento: ${ev.t} — ${when}`;
  let sent = 0, failed = 0, reason = '';const names = [];
  const post = async (toAddr, subj, html, text) => {
    const r = await fetch('https://api.resend.com/emails', { method: 'POST', headers: { Authorization: 'Bearer ' + apiKey, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from, to: [toAddr], subject: subj, html, text, attachments: attach }) });
    if (!r.ok) { let m = 'errore ' + r.status; try { const j = await r.json(); m = (j && (j.message || j.error && j.error.message || j.name)) || m } catch (e) {} throw new Error(m) }
  };
  await Promise.all(to.map(async p => {
    const { html, text } = buildEmail(ev, (p.name || '').split(' ')[0] || 'ciao');
    try { await post(p.email.trim(), subject, html, text); sent++; names.push(p.name || p.email) }
    catch (e) { failed++; if (!reason) reason = e.message }
  }));

  // promemoria a chi ha creato l'evento
  let promemoria = 'senza_email';
  if (ev.creatorEmail) {
    const { html, text } = buildEmail(ev, (me.name || '').split(' ')[0] || 'ciao', { reminder: true, invited: names, failed, noMail: senzaEmail });
    try { await post(ev.creatorEmail, `Promemoria: hai creato "${ev.t}" — ${when}`, html, text); promemoria = 'inviato' }
    catch (e) { promemoria = 'fallito'; if (!reason) reason = e.message }
  }
  return res.status(200).json({ sent, failed, reason, names, senzaEmail, promemoria });
};
module.exports._test = { buildEmail, ics, longDate };

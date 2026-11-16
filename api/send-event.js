// TEDxLerici HUB · invio email per un nuovo evento (Vercel Serverless Function)
//
// Variabili d'ambiente su Vercel (Project → Settings → Environment Variables):
//   RESEND_API_KEY   chiave del servizio email Resend (https://resend.com)
//   MAIL_FROM        mittente, es.  TEDxLerici HUB <hub@tuodominio.it>   (dominio verificato su Resend)
//   SUPABASE_URL, SUPABASE_ANON_KEY   (opzionali: se mancano si usano quelli pubblici del sito)
//
// Sicurezza: la funzione NON accetta indirizzi email dal browser. Verifica chi chiama con il suo token Supabase,
// controlla che sia team lead o superadmin e ricava i destinatari dai profili nel database.

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

function buildEmail(ev, who) {
  const online = ev.mode === 'online';
  const place = online ? 'Online' + (ev.where ? ' · ' + ev.where : '') : (ev.where || 'Da definire') + ' (in presenza)';
  const rows = [['Quando', longDate(ev.d) + (ev.h ? ' · ore ' + ev.h : '')], ['Dove', place]];
  if (online && ev.link) rows.push(['Link della call', ev.link]);
  const row = ([k, v]) => `<tr><td style="padding:8px 14px 8px 0;color:#777;font-size:13px;vertical-align:top;white-space:nowrap">${k}</td><td style="padding:8px 0;font-size:15px;color:#111">${k === 'Link della call' ? `<a href="${esc(v)}" style="color:#e62b1e;font-weight:700">${esc(v)}</a>` : esc(v)}</td></tr>`;
  const html = `<div style="font-family:Helvetica,Arial,sans-serif;max-width:560px;margin:0 auto;padding:24px;color:#111">
<div style="font-size:12px;letter-spacing:.14em;color:#e62b1e;font-weight:700">TEDXLERICI HUB · NUOVO EVENTO</div>
<h1 style="font-size:24px;margin:8px 0 16px">${esc(ev.t)}</h1>
<table style="border-collapse:collapse;width:100%;border-top:1px solid #eee;border-bottom:1px solid #eee">${rows.map(row).join('')}</table>
${ev.desc ? `<p style="font-size:15px;line-height:1.55;margin:18px 0;white-space:pre-line">${esc(ev.desc)}</p>` : ''}
${online && ev.link ? `<p><a href="${esc(ev.link)}" style="display:inline-block;background:#e62b1e;color:#fff;padding:11px 20px;border-radius:8px;text-decoration:none;font-weight:700">Apri la call</a></p>` : ''}
<p style="font-size:12px;color:#999;margin-top:26px">Ciao ${esc(who)}, ricevi questa email perché l'evento riguarda ${ev.teamName ? 'il team ' + esc(ev.teamName) : 'tutta la crew'}. In allegato trovi l'invito da aggiungere al calendario.</p></div>`;
  const text = [`NUOVO EVENTO · ${ev.t}`, '', ...rows.map(([k, v]) => `${k}: ${v}`), ev.desc ? '\n' + ev.desc : ''].join('\n');
  return { html, text };
}

function ics(ev) {
  const z = s => s.replace(/[-:]/g, '');
  const start = z(ev.d) + 'T' + z(ev.h || '09:00') + '00';
  const fold = s => String(s).replace(/\\/g, '\\\\').replace(/;/g, '\;').replace(/,/g, '\\,').replace(/\r?\n/g, '\\n');
  const loc = ev.mode === 'online' ? (ev.link || 'Online') : (ev.where || '');
  return ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//TEDxLerici HUB//IT', 'METHOD:PUBLISH', 'BEGIN:VEVENT',
    `UID:${Date.now()}-${Math.random().toString(36).slice(2)}@tedxlerici-hub`, `DTSTAMP:${new Date().toISOString().replace(/[-:]|\.\d+/g, '')}`,
    `DTSTART:${start}`, `SUMMARY:${fold(ev.t)}`, `LOCATION:${fold(loc)}`,
    `DESCRIPTION:${fold((ev.desc || '') + (ev.mode === 'online' && ev.link ? '\nLink della call: ' + ev.link : ''))}`,
    'END:VEVENT', 'END:VCALENDAR'].join('\r\n');
}

module.exports = async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
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

  // destinatari ricavati dal database: persone del/i team indicati (o tutta la crew) + superadmin, mai chi crea l'evento, mai ospiti
  const to = profiles.filter(p => p.id !== uid && p.email && p.role !== 'guest' && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(p.email) &&
    (p.role === 'superadmin' || !teams.length || teams.includes(p.team))).slice(0, 80);
  if (!to.length) return res.status(200).json({ sent: 0, failed: 0 });

  const attach = [{ filename: 'invito.ics', content: Buffer.from(ics(ev), 'utf8').toString('base64') }];
  const subject = `Nuovo evento: ${ev.t} — ${longDate(ev.d).replace(/^\S+\s/, '')}${ev.h ? ' ore ' + ev.h : ''}`;
  let sent = 0, failed = 0;
  await Promise.all(to.map(async p => {
    const { html, text } = buildEmail(ev, (p.name || '').split(' ')[0] || 'ciao');
    try {
      const r = await fetch('https://api.resend.com/emails', { method: 'POST', headers: { Authorization: 'Bearer ' + apiKey, 'Content-Type': 'application/json' },
        body: JSON.stringify({ from, to: [p.email], subject, html, text, attachments: attach }) });
      r.ok ? sent++ : failed++;
    } catch (e) { failed++ }
  }));
  return res.status(200).json({ sent, failed });
};
module.exports._test = { buildEmail, ics, longDate };

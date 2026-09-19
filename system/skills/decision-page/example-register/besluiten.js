// Answers live in localStorage so a half-finished pass survives a reload.
// Shape per decision: { keus: 'o0', notitie: 'free text' } -- either may be absent.
// v1 stored a bare string; read that shape too rather than dropping older answers.
// Language follows the document: <html lang="nl"> gets Dutch, anything else
// English. The page's own text (the decisions) is written in the language of
// the context it belongs to; these are only the controls around it. Add a
// language by adding a key, not by editing the code below.
const TAAL = {
  nl: { teller: (a, n, t) => `${a} van ${n} beantwoord${t ? ` \u00b7 ${t} toegelicht` : ''}`,
        nietGekozen: 'nog niet gekozen', nietGekozenExport: 'NOG NIET GEKOZEN',
        keuze: 'keuze', toelichting: 'toelichting',
        gekopieerd: 'gekopieerd', wisVraag: 'Alle keuzes en toelichtingen wissen?' },
  en: { teller: (a, n, t) => `${a} of ${n} answered${t ? ` \u00b7 ${t} annotated` : ''}`,
        nietGekozen: 'not chosen yet', nietGekozenExport: 'NOT CHOSEN YET',
        keuze: 'choice', toelichting: 'note',
        gekopieerd: 'copied', wisVraag: 'Clear every choice and note?' },
};
const T = TAAL[document.documentElement.lang] || TAAL.en;

const KEY = 'voorbeeld-plaatkast';           // unique per page; the template's placeholder

function load() {
  let rauw = {};
  try { rauw = JSON.parse(localStorage.getItem(KEY)) || {}; } catch { return {}; }
  const uit = {};
  for (const [id, w] of Object.entries(rauw)) uit[id] = typeof w === 'string' ? { keus: w } : (w || {});
  return uit;
}
let staat = load();
const bewaar = () => { try { localStorage.setItem(KEY, JSON.stringify(staat)); } catch {} };
const vak = (id) => (staat[id] ||= {});

function groei(ta) { ta.style.height = 'auto'; ta.style.height = `${ta.scrollHeight}px`; }

function ververs() {
  const rijen = [];
  document.querySelectorAll('article[data-id]').forEach(art => {
    const id = art.dataset.id;
    const { keus, notitie } = staat[id] || {};
    const knop = keus ? art.querySelector(`input[value="${CSS.escape(keus)}"]`) : null;
    if (knop) knop.checked = true;
    const ta = art.querySelector('textarea');
    if (ta && ta.value !== (notitie || '')) { ta.value = notitie || ''; groei(ta); }
    art.classList.toggle('af', !!knop);
    art.classList.toggle('heeft-notitie', !!(notitie || '').trim());
    rijen.push({ id, titel: art.dataset.titel, keus: knop ? knop.dataset.kort : null, notitie: (notitie || '').trim() });
  });

  const af = rijen.filter(r => r.keus).length;
  const met = rijen.filter(r => r.notitie).length;
  document.getElementById('teller').textContent =
    T.teller(af, rijen.length, met);
  document.getElementById('balk').style.setProperty('--af', `${(af / rijen.length) * 100}%`);
  document.getElementById('uitslag').innerHTML = rijen.map(r => {
    const keus = r.keus ? r.keus : `<span class="leeg">${T.nietGekozen}</span>`;
    const noot = r.notitie ? `<span class="noot">${r.notitie.replace(/[<>&]/g, c => ({'<':'&lt;','>':'&gt;','&':'&amp;'}[c]))}</span>` : '';
    return `<tr><td>${r.id}</td><td>${r.titel}</td><td>${keus}${noot}</td></tr>`;
  }).join('');
}

document.addEventListener('change', e => {
  if (e.target.matches('input[type=radio][name^="b-"]')) {
    vak(e.target.closest('article').dataset.id).keus = e.target.value;
    bewaar(); ververs();
  }
});

document.addEventListener('input', e => {
  if (e.target.matches('textarea[data-notitie]')) {
    vak(e.target.closest('article').dataset.id).notitie = e.target.value;
    groei(e.target); bewaar();
    clearTimeout(e.target._t);
    e.target._t = setTimeout(ververs, 400);   // keep the summary quiet while typing
  }
});

document.getElementById('kopieer').addEventListener('click', async () => {
  const regels = [...document.querySelectorAll('article[data-id]')].map(art => {
    const k = art.querySelector('input:checked');
    const n = (art.querySelector('textarea')?.value || '').trim();
    let r = `${art.dataset.id}  ${art.dataset.titel}\n    ${T.keuze}: ${k ? k.dataset.kort : T.nietGekozenExport}`;
    if (n) r += `\n    ${T.toelichting}: ${n.replace(/\n/g, '\n                 ')}`;
    return r;
  });
  await navigator.clipboard.writeText(`Plaatkast, open besluiten, 17 september 2026\n\n${regels.join('\n\n')}\n`);
  const b = document.getElementById('kopieer'), was = b.textContent;
  b.textContent = T.gekopieerd; setTimeout(() => { b.textContent = was; }, 1400);
});

document.getElementById('wis').addEventListener('click', () => {
  if (!confirm(T.wisVraag)) return;
  staat = {}; bewaar();
  document.querySelectorAll('input[type=radio]').forEach(i => { i.checked = false; });
  document.querySelectorAll('textarea[data-notitie]').forEach(t => { t.value = ''; groei(t); });
  ververs();
});

// Theme switch. "auto" removes the stamp so prefers-color-scheme decides again.
const TKEY = 'voorbeeld-plaatkast-thema';
const knoppen = [...document.querySelectorAll('.thema button')];
function zetThema(keuze) {
  if (keuze === 'auto') document.documentElement.removeAttribute('data-theme');
  else document.documentElement.setAttribute('data-theme', keuze);
  try { localStorage.setItem(TKEY, keuze); } catch {}
  knoppen.forEach(b => b.setAttribute('aria-pressed', String(b.dataset.thema === keuze)));
}
knoppen.forEach(b => b.addEventListener('click', () => zetThema(b.dataset.thema)));
let bewaardThema = 'auto';
try { bewaardThema = localStorage.getItem(TKEY) || 'auto'; } catch {}
zetThema(bewaardThema);

ververs();

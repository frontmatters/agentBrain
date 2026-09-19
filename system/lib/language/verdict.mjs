/**
 * Is this identifier written in a language other than English?
 *
 * Built for the naming rule "code is English", which needs two questions answered, not
 * one: is the word Dutch, AND is it not also English. A hand-kept list answers the first
 * and forgets the second, which is how `open`, `map` and `meet` came to be flagged as
 * Dutch -- each is the same word in both languages, and a gate that trips on them pushes
 * someone towards a worse name.
 *
 * Real dictionaries answer both. `bewaar` is in the Dutch list and not the English one:
 * foreign. `open` is in both: not evidence of anything.
 *
 * Word lists come from the cache that `fetch-wordlists.sh` fills; see `wordlists.tsv` for
 * what exists and how to add a language. Nothing here is vendored, so a missing cache is a
 * normal state and the caller is told rather than silently given an empty verdict.
 */
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const CACHE = process.env.AGENTBRAIN_WORDLIST_CACHE
  ?? join(homedir(), '.cache/agentbrain/wordlists');

/** Loads every `<code>.txt` in the cache. A list dropped in by hand counts. */
function loadLists() {
  if (!existsSync(CACHE)) return new Map();
  const uit = new Map();
  for (const f of readdirSync(CACHE)) {
    const m = /^([a-z]{2})\.txt$/.exec(f);
    if (!m) continue;
    const woorden = new Set(
      readFileSync(join(CACHE, f), 'utf8')
        .split('\n')
        .map((w) => w.trim().toLowerCase())
        .filter((w) => w.length >= 2 && /^[a-zà-ÿ'-]+$/.test(w)),
    );
    uit.set(m[1], woorden);
  }
  return uit;
}

const LISTS = loadLists();
export const availableLanguages = [...LISTS.keys()].sort();
export const hasLists = LISTS.size > 0;

/** Segments of an identifier: camelCase, kebab and snake, nothing dropped. */
export const segments = (id) =>
  id.replace(/([a-z0-9])([A-Z])/g, '$1 $2').replace(/[-_]/g, ' ').toLowerCase().split(/\s+/).filter(Boolean);

/**
 * Separable-verb particles. Dutch glues these onto a verb (`slaat … op`, `dient … in`), and
 * in camelCase they surface as a short trailing segment. Two letters, so a dictionary alone
 * will not settle them: `in`, `om` and `na` are English words too. Trusted only as the LAST
 * segment of a multi-segment name, where English almost never leaves a bare one.
 */
const PARTICLES = new Set('op af aan uit bij toe mee heen weg in om na'.split(' '));

/**
 * Words a dictionary cannot settle, kept short and named rather than folded into the
 * vocabulary. Two kinds only:
 *
 *   - Dutch words that are also common English, where the camelCase POSITION decides:
 *     `van` is a vehicle in English but `statusVan` and `vanLabel` are Dutch. Counted only
 *     as a first or last segment of a multi-segment name, never mid-word.
 *   - Terms this codebase invented, which are in no dictionary by definition.
 *
 * Anything that a dictionary already answers does not belong here. The list staying short
 * is the signal that the dictionaries are doing the work.
 */
const POSITIONEEL = new Set('van naar bij'.split(' '));
const EIGEN_TERMEN = new Set('kijklink deellink werkbank beeldbank rouwkaart nabestaande opdrachtgever'.split(' '));

/**
 * A compound written without a seam: `foutmelding`, `proefaanvragen`.
 *
 * BOTH halves have to be words, which is what makes it a compound. Matching one half was
 * enough at first and found `eline` inside `timeline`, then reported an English word as
 * Dutch. The remainder test costs nothing and removes the whole class.
 */
function inCompound(token, woorden, engels) {
  if (token.length < 7) return null;
  for (const w of woorden) {
    if (w.length < 4 || engels.has(w)) continue;
    let rest = null;
    if (token.startsWith(w)) rest = token.slice(w.length);
    else if (token.endsWith(w)) rest = token.slice(0, -w.length);
    // Four, not three: OpenTaal carries given names, so `tim` made `timeline` a compound.
    if (rest && rest.length >= 4 && woorden.has(rest)) return w;
  }
  return null;
}

/**
 * Every foreign word this identifier carries, with the language and the reason.
 * `taal` defaults to Dutch; pass another code to ask about German or French.
 */
export function foreignHits(id, taal = 'nl') {
  const woorden = LISTS.get(taal);
  const engels = LISTS.get('en') ?? new Set();
  if (!woorden) return [];
  const segs = segments(id);
  const hits = [];
  segs.forEach((s, i) => {
    if (s.length >= 3 && woorden.has(s) && !engels.has(s)) { hits.push(s); return; }
    if (i > 0 && i === segs.length - 1 && PARTICLES.has(s)) { hits.push(s); return; }
    if (segs.length > 1 && (i === 0 || i === segs.length - 1) && POSITIONEEL.has(s)) { hits.push(s); return; }
    if (EIGEN_TERMEN.has(s)) { hits.push(s); return; }
    const inner = inCompound(s, woorden, engels);
    if (inner) hits.push(`${s} (${inner})`);
  });
  return hits;
}

/** True when the identifier carries any word of `taal` that English does not share. */
export const isForeign = (id, taal = 'nl') => foreignHits(id, taal).length > 0;

/**
 * Three verdicts, because two were hiding the interesting case.
 *
 *   red    carries a word that is Dutch and not common English: rename it.
 *   amber  carries a word that BOTH languages have -- `open`, `map`, `datum`, `status`.
 *          A binary verdict had to pick one and was wrong either way: calling them Dutch
 *          pushes someone to a worse name, calling them English hides a Dutch intent
 *          behind a word that happens to exist in both. Amber puts it to a person.
 *   green  nothing foreign found.
 *
 * Red wins over amber: one certain word settles the name.
 */
/**
 * @param {string} id
 * @param {string} taal
 * @param {{bekend?: Record<string, {oordeel: 'en'|'nl'}>}} [opties]
 *   `bekend` is the caller's whitelist: an ambiguous word it has already judged in its own
 *   context. A dictionary cannot tell whether `meet` is the English verb or the Dutch one;
 *   the codebase can, once, and then the answer stops being a question. Words absent from
 *   it stay amber, so a new ambiguity surfaces instead of passing silently.
 */
export function classify(id, taal = 'nl', opties = {}) {
  const woorden = LISTS.get(taal);
  const engels = LISTS.get('en') ?? new Set();
  if (!woorden) return { level: 'green', hits: [], ambigu: [] };

  const bekend = opties.bekend ?? {};
  const hits = foreignHits(id, taal);
  const ambigu = [];
  for (const s of segments(id)) {
    if (s.length < 3 || !woorden.has(s) || !engels.has(s) || hits.includes(s)) continue;
    const oordeel = bekend[s]?.oordeel;
    if (oordeel === 'en') continue;          // beslist: hier Engels
    if (oordeel === 'nl') hits.push(s);      // beslist: hier Nederlands
    else ambigu.push(s);                     // nog niet beslist
  }
  const level = hits.length ? 'red' : ambigu.length ? 'amber' : 'green';
  return { level, hits, ambigu };
}

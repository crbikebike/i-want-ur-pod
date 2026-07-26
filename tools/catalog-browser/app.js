/* Catalog workbench.

   The job is not "browse podcasts". It is "decide whether 1,597 detected groupings are
   real". So the IA has three modes rather than a page with tabs:

     Browse   the catalog, faceted on every axis that matters
     Review   a queue — one decision per screen, keyboard-driven
     System   what this pipeline is and what of it actually exists

   Facets apply to the queue as well as the grid, so "review only limited-series arcs"
   is one click. Progress is always on screen because the work is finite and long.

   No framework, no build step. Data: /api/catalog (curation/arc-bakeoff/build-catalog-index.py). */

const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const el = (t, c, x) => { const n = document.createElement(t); if (c) n.className = c; if (x != null) n.textContent = x; return n; };

const state = {
  data: null, verdicts: {},
  mode: 'browse', slug: null,
  f: { rule: null, feed: null, review: null, cat: '', conf: null, tflag: null },
  q: '', cursor: 0, qi: 0, arc: null, theme: null, gtheme: null,
};

/* ---------- shared episode vocabulary ----------
   Episode themes are one catalog-wide taxonomy, not a per-show one, so shows carry
   indices into this list rather than their own vocabularies. That is what makes
   "what else is like this episode?" reach across shows at all. */
const epVocab = () => (state.data && state.data.epVocab) || [];
const themeAt = i => epVocab()[i] || null;

/* The show's own slice of the shared vocabulary, resolved and sorted by weight. */
const showThemes = s => (s.themesUsed || [])
  .map(([gi, count]) => { const t = themeAt(gi); return t ? { ...t, gi, count } : null; })
  .filter(Boolean);

/* Every show that uses a theme, for the cross-show theme page. */
function showsUsing(gi) {
  return state.data.shows
    .map(s => ({ s, n: (s.themesUsed || []).find(([i]) => i === gi) }))
    .filter(x => x.n)
    .map(x => ({ s: x.s, count: x.n[1] }))
    .sort((a, b) => b.count - a.count);
}

const art = u => (u || '').replace(/\/\d+x\d+bb\./, '/300x300bb.');
const initials = t => t.replace(/^(the|a|an)\s+/i, '').split(/\s+/).slice(0, 2).map(w => w[0] || '').join('').toUpperCase();
const MON = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const fmtDate = iso => { if (!iso) return ''; const [y, m, d] = iso.split('-'); return `${MON[+m]} ${+d} ${y}`; };

/* ---------- data ---------- */
async function boot() {
  const [cat, ver] = await Promise.all([
    fetch('/api/catalog').then(r => r.ok ? r.json() : Promise.reject(new Error('catalog-index.json not built'))),
    fetch('/api/verdicts').then(r => r.json()).catch(() => ({})),
  ]);
  state.data = cat; state.verdicts = ver;
  fromHash();
  render();
}

async function saveVerdict(body) {
  const res = await fetch('/api/verdicts', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
  });
  if (!res.ok) { console.error('verdict rejected', await res.text()); return; }
  const out = await res.json();
  if (out.verdicts) state.verdicts[body.slug] = out.verdicts; else delete state.verdicts[body.slug];
}

/* ---------- judgement state ---------- */
const rec = slug => state.verdicts[slug] || {};
const arcVerdict = (slug, i) => (rec(slug).arcs || {})[String(i)]?.v || null;
const themeVerdict = (slug, s) => (rec(slug).themes || {})[s]?.v || null;

function showState(s) {
  const r = rec(s.slug);
  if (r.show) return 'done';
  const total = s.arcs.length + (s.themesUsed || []).length;
  if (!total) return 'none';
  const judged = Object.keys(r.arcs || {}).length + Object.keys(r.themes || {}).length;
  if (!judged) return 'todo';
  return judged >= total ? 'done' : 'mixed';
}

function totals() {
  let items = 0, judged = 0;
  for (const s of state.data.shows) {
    items += s.arcs.length + (s.themesUsed || []).length;
    const r = rec(s.slug);
    judged += Object.keys(r.arcs || {}).length + Object.keys(r.themes || {}).length;
  }
  return { items, judged };
}

/* ---------- filtering ---------- */
function matches(s, q) {
  if (!q) return true;
  if (s.title.toLowerCase().includes(q) || (s.author || '').toLowerCase().includes(q)) return true;
  if (s.arcs.some(a => a.n.toLowerCase().includes(q))) return true;
  if (showThemes(s).some(t => t.n.toLowerCase().includes(q))) return true;
  return s.eps.some(e => e[0].toLowerCase().includes(q));   // episode titles matter — "OceanGate"
}

function visible() {
  const q = state.q.trim().toLowerCase();
  const { rule, feed, review, cat, conf, tflag } = state.f;
  return state.data.shows.filter(s => {
    if (conf && !(s.conf && s.conf[conf])) return false;
    if (tflag === 'spec' && !showThemes(s).some(t => t.spec)) return false;
    if (tflag === 'junk' && !showThemes(s).some(t => t.junk)) return false;
    if (tflag === 'audit' && !(s.auditFlags || []).length) return false;
    if (cat && s.category !== cat) return false;
    if (feed && (s.small ? s.small.key : 'normal') !== feed) return false;
    if (review && showState(s) !== review) return false;
    if (rule) {
      if (rule === 'themed') { if (!(s.themesUsed || []).length) return false; }
      else if (rule.startsWith('group:')) { if (s.group !== rule.slice(6)) return false; }
      else if (!s.patterns.includes(rule)) return false;
    }
    return matches(s, q);
  });
}

/* Every judgeable thing, in corpus order, honouring the active facets. */
function queue() {
  const out = [];
  for (const s of visible()) {
    s.arcs.forEach((a, i) => out.push({
      kind: 'arc', s, i, key: `${s.slug}#a${i}`, name: a.n, season: a.s,
      rule: a.p, count: a.c, verdict: arcVerdict(s.slug, i),
      eps: s.eps.filter(e => e[4] === i),
    }));
    showThemes(s).forEach(t => out.push({
      kind: 'theme', s, i: t.gi, key: `${s.slug}#t${t.s}`, name: t.n, def: t.d, slugId: t.s,
      count: t.count, verdict: themeVerdict(s.slug, t.s),
      eps: s.eps.filter(e => e[5] === t.gi),
    }));
  }
  return out;
}

/* ---------- routing ---------- */
function go(hash) { location.hash = hash; }
function fromHash() {
  const h = location.hash;
  const m = /^#\/show\/(.+)$/.exec(h);
  const t = /^#\/theme\/(.+)$/.exec(h);
  if (m) { state.slug = decodeURIComponent(m[1]); state.gtheme = null; state.arc = state.theme = null; }
  else if (t) { state.gtheme = decodeURIComponent(t[1]); state.slug = null; }
  else {
    state.slug = null; state.gtheme = null;
    state.mode = h === '#/review' ? 'review' : h === '#/system' ? 'system' : 'browse';
  }
  if (state.data) render();
}
window.addEventListener('hashchange', () => { fromHash(); window.scrollTo(0, 0); });

/* ---------- shell ---------- */
const MODES = [
  { k: 'browse', key: 'B', label: 'Browse', hash: '#/browse' },
  { k: 'review', key: 'R', label: 'Review', hash: '#/review' },
  { k: 'system', key: 'S', label: 'System', hash: '#/system' },
];

function render() {
  const mode = (state.slug || state.gtheme) ? 'browse' : state.mode;
  document.body.dataset.mode = mode;
  renderModes(mode);
  renderFacets(mode);
  renderProgress();

  if (state.gtheme) return renderTheme();
  if (state.slug) return renderDetail();
  if (state.mode === 'review') return renderReview();
  if (state.mode === 'system') return renderSystem();
  renderBrowse();
}

function renderModes(mode) {
  const nav = $('#modes');
  const q = queue().filter(x => !x.verdict).length;
  nav.replaceChildren();
  MODES.forEach(m => {
    const b = el('button', 'mode');
    b.setAttribute('aria-current', m.k === mode ? 'page' : 'false');
    b.appendChild(el('span', 'mode-k', m.key));
    b.appendChild(el('span', null, m.label));
    if (m.k === 'browse') b.appendChild(el('span', 'mode-n', String(visible().length)));
    if (m.k === 'review') b.appendChild(el('span', 'mode-n', String(q)));
    b.onclick = () => { state.qi = 0; go(m.hash); };
    nav.appendChild(b);
  });
}

function facetGroup(title, items, active, onPick) {
  const g = el('div', 'fgroup');
  g.appendChild(el('h2', null, title));
  items.forEach(([key, label, n]) => {
    const b = el('button', 'facet');
    b.setAttribute('aria-pressed', String(active === key));
    b.appendChild(el('span', null, label));
    if (n != null) b.appendChild(el('i', null, String(n)));
    b.onclick = () => { onPick(active === key ? null : key); };
    g.appendChild(b);
  });
  return g;
}

function renderFacets(mode) {
  const box = $('#facets');
  box.replaceChildren();
  if (mode === 'system') return;

  const shows = state.data.shows;
  const set = (k, v) => { state.f[k] = v; state.cursor = 0; state.qi = 0; render(); };
  const count = fn => shows.filter(fn).length;

  // How sure the model was. Only model-proposed themes carry this — regex arcs have no
  // confidence to report, so the group hides itself until some show has one.
  const conf = k => shows.reduce((n, s) => n + ((s.conf && s.conf[k]) || 0), 0);
  if (conf('l') + conf('m') + conf('h')) {
    box.appendChild(facetGroup('Model confidence', [
      ['l', 'Low', conf('l')],
      ['m', 'Medium', conf('m')],
      ['h', 'High', conf('h')],
    ], state.f.conf, v => set('conf', v)));
  }

  // Theme-quality facets. These are the review queue for a later merge pass: themes that
  // only ever fired on one show, and definitions that read as catch-alls.
  const flagged = {
    spec: shows.filter(x => showThemes(x).some(t => t.spec)).length,
    junk: shows.filter(x => showThemes(x).some(t => t.junk)).length,
    audit: shows.filter(x => (x.auditFlags || []).length).length,
  };
  if (flagged.spec + flagged.junk + flagged.audit) {
    box.appendChild(facetGroup('Theme quality', [
      ['spec', 'Show-specific theme', flagged.spec],
      ['junk', 'Junk-drawer suspect', flagged.junk],
      ['audit', 'Audit flagged', flagged.audit],
    ], state.f.tflag, v => set('tflag', v)));
  }

  box.appendChild(facetGroup('Review state', [
    ['todo', 'Not started', count(s => showState(s) === 'todo')],
    ['mixed', 'Part-judged', count(s => showState(s) === 'mixed')],
    ['done', 'Settled', count(s => showState(s) === 'done')],
  ], state.f.review, v => set('review', v)));

  const pats = Object.entries(state.data.patterns);
  box.appendChild(facetGroup('Detected by', [
    ...(shows.some(s => (s.themesUsed || []).length)
      ? [['themed', 'Model themes', count(s => (s.themesUsed || []).length)]] : []),
    ...pats.sort((a, b) => b[1].shows - a[1].shows).map(([k, v]) => [k, v.label, v.shows]),
  ], state.f.rule, v => set('rule', v)));

  const feedKeys = {};
  shows.forEach(s => { const k = s.small ? s.small.key : 'normal'; feedKeys[k] = (feedKeys[k] || 0) + 1; });
  box.appendChild(facetGroup('Feed', Object.entries(feedKeys)
    .filter(([k]) => k !== 'normal')
    .sort((a, b) => b[1] - a[1])
    .map(([k, n]) => [k, ({ sampler: 'Opening only', windowed: 'Recent only',
      'short-series': 'Short series', 'empty-feed': 'Empty', 'unknown-short': 'Short, unclear' })[k] || k, n]),
    state.f.feed, v => set('feed', v)));

  const cats = [...new Set(shows.map(s => s.category).filter(Boolean))].sort();
  const g = el('div', 'fgroup');
  g.appendChild(el('h2', null, 'Category'));
  const sel = el('select', 'search');
  sel.style.height = '32px'; sel.style.fontSize = '.8rem';
  sel.appendChild(new Option('Any', ''));
  cats.forEach(c => sel.appendChild(new Option(c, c)));
  sel.value = state.f.cat;
  sel.onchange = e => set('cat', e.target.value);
  g.appendChild(sel);
  box.appendChild(g);

  if (state.f.rule || state.f.feed || state.f.review || state.f.cat || state.f.conf || state.f.tflag) {
    const clear = el('button', 'facet-clear', 'Clear filters');
    clear.onclick = () => { state.f = { rule: null, feed: null, review: null, cat: '', conf: null, tflag: null };
      state.cursor = 0; state.qi = 0; render(); };
    box.appendChild(clear);
  }
}

function renderProgress() {
  const { items, judged } = totals();
  const p = $('#progress');
  p.replaceChildren();
  const l = el('div', 'progress-l');
  l.appendChild(el('span', null, 'Judged'));
  const b = el('span'); b.appendChild(el('b', null, String(judged)));
  b.append(' / ' + items); l.appendChild(b);
  p.appendChild(l);
  const meter = el('div', 'meter');
  const fill = el('span'); fill.style.width = (items ? (judged / items) * 100 : 0) + '%';
  meter.appendChild(fill); p.appendChild(meter);
}

/* ---------- browse ---------- */
function renderBrowse() {
  const shows = visible();
  $('#crumb').textContent = `${shows.length} shows`;
  const view = $('#view');
  view.replaceChildren();
  if (!shows.length) { view.appendChild(el('p', 'empty', 'Nothing matches those filters.')); return; }
  if (state.cursor >= shows.length) state.cursor = 0;

  const grid = el('div', 'grid');
  shows.forEach((s, i) => {
    const c = showCard(s, i);
    c.style.animationDelay = Math.min(i, 18) * 14 + 'ms';
    grid.appendChild(c);
  });
  view.appendChild(grid);
  const h = el('p', 'hint');
  h.append('Move ');
  h.appendChild(el('span', 'kbd', 'j'));
  h.append(' ');
  h.appendChild(el('span', 'kbd', 'k'));
  h.append(' · open ');
  h.appendChild(el('span', 'kbd', '↵'));
  h.append(' · search ');
  h.appendChild(el('span', 'kbd', '/'));
  view.appendChild(h);
}

function showCard(s, i) {
  const st = showState(s);
  const c = el('button', 'card p-' + (st === 'none' && (s.themesUsed || []).length ? 'model' : st));
  c.onclick = () => go('#/show/' + encodeURIComponent(s.slug));
  if (i === state.cursor) c.dataset.cursor = '1';

  const a = el('div', 'card-art');
  if (s.art) a.style.backgroundImage = `url("${art(s.art)}")`;
  else a.appendChild(el('span', null, initials(s.title)));
  c.appendChild(a);
  c.appendChild(el('div', 'card-title', s.title));
  c.appendChild(el('div', 'card-sub', s.network || s.author || ''));

  const foot = el('div', 'card-foot');
  if ((s.themesUsed || []).length) foot.appendChild(el('span', 'tag model', `${s.themesUsed.length} themes`));
  if (s.arcs.length) foot.appendChild(el('span', 'tag on', `${s.arcs.length} arc${s.arcs.length > 1 ? 's' : ''}`));
  if (s.small) foot.appendChild(el('span', 'tag warn', s.small.label));
  else if (!s.arcs.length && !(s.themesUsed || []).length) {
    const g = state.data.noArcGroups[s.group];
    foot.appendChild(el('span', 'tag none', g ? g.label : 'no arcs'));
  }
  c.appendChild(foot);
  return c;
}

/* ---------- review ---------- */
function renderReview() {
  const all = queue();
  const todo = all.filter(x => !x.verdict);
  $('#crumb').textContent = `${todo.length} to judge`;
  const view = $('#view');
  view.replaceChildren();

  if (!todo.length) {
    const d = el('div', 'done-state');
    d.appendChild(el('h2', null, all.length ? 'Nothing left here' : 'Nothing matches those filters'));
    d.appendChild(el('p', null, all.length
      ? 'Every grouping in this slice has a verdict. Widen the filters for more.'
      : 'Clear a filter to bring items back.'));
    view.appendChild(d);
    return;
  }
  if (state.qi >= todo.length) state.qi = 0;
  const it = todo[state.qi];

  const wrap = el('div', 'queue');
  const top = el('div', 'q-top');
  top.appendChild(el('span', 'q-pos', `${state.qi + 1} of ${todo.length}`));
  const skip = el('button', 'q-skip', 'Skip →');
  skip.onclick = () => { state.qi = Math.min(todo.length - 1, state.qi + 1); renderReview(); };
  top.appendChild(skip);
  wrap.appendChild(top);

  const card = el('div', 'q-card');
  const head = el('div', 'q-head');
  const a = el('div', 'q-art');
  if (it.s.art) a.style.backgroundImage = `url("${art(it.s.art)}")`;
  head.appendChild(a);
  const meta = el('div');
  const showLink = el('div', 'q-show', it.s.title);
  meta.appendChild(showLink);
  meta.appendChild(el('h2', 'q-name', it.name));
  const mrow = el('div', 'q-meta');
  mrow.appendChild(el('span', it.kind === 'theme' ? 'tag model' : 'tag',
    it.kind === 'theme' ? 'model theme' : (state.data.patterns[it.rule]?.label || it.rule)));
  mrow.appendChild(el('span', 'tag', `${it.count} episodes`));
  if (it.season != null) mrow.appendChild(el('span', 'tag', 'S' + it.season));
  meta.appendChild(mrow);
  head.appendChild(meta);
  card.appendChild(head);

  if (it.def) card.appendChild(el('p', 'q-def', it.def));

  const eps = el('div', 'q-eps');
  it.eps.slice(0, 12).forEach(e => {
    const row = el('div', 'q-ep');
    row.appendChild(el('span', null, fmtDate(e[1])));
    row.appendChild(el('div', null, e[0]));
    eps.appendChild(row);
  });
  if (it.eps.length > 12) eps.appendChild(el('p', 'q-more', `+ ${it.eps.length - 12} more`));
  card.appendChild(eps);

  const actions = el('div', 'q-actions');
  [['right', 'Real', '1'], ['wrong', 'Not real', '2'], ['unsure', 'Unsure', '3']].forEach(([v, label, key]) => {
    const b = el('button', 'vbtn ' + v);
    b.appendChild(el('span', null, label));
    b.appendChild(el('span', 'k', key));
    b.onclick = () => judge(it, v);
    actions.appendChild(b);
  });
  card.appendChild(actions);
  wrap.appendChild(card);

  const open = el('button', 'q-skip', 'Open ' + it.s.title + ' →');
  open.onclick = () => go('#/show/' + encodeURIComponent(it.s.slug));
  wrap.appendChild(open);
  view.appendChild(wrap);
}

async function judge(it, verdict) {
  const body = it.kind === 'arc'
    ? { slug: it.s.slug, kind: 'arc', index: it.i, verdict, name: it.name, count: it.count }
    : { slug: it.s.slug, kind: 'theme', theme: it.slugId, verdict, name: it.name };
  await saveVerdict(body);
  render();                       // the item leaves the queue, so the next one slides in
}


/* ---------- theme detail: the point of the whole exercise ----------
   One theme, every show that uses it. If this page is empty or single-show for most
   themes, the vocabulary did not cut across the catalog and the run failed. */
function renderTheme() {
  const gi = epVocab().findIndex(t => t.s === state.gtheme);
  const t = gi >= 0 ? epVocab()[gi] : null;
  const view = $('#view');
  view.replaceChildren();
  $('#crumb').textContent = '';

  const back = el('button', 'back', '\u2190 Catalog');
  back.onclick = () => go('#/browse');
  view.appendChild(back);

  if (!t) { view.appendChild(el('p', 'empty', 'No such theme.')); return; }

  const head = el('div', 'dmeta');
  head.appendChild(el('div', 'dcat', 'Episode theme'));
  head.appendChild(el('h1', 'dtitle', t.n));
  head.appendChild(el('p', 'ddesc', t.d));

  const stats = el('div', 'dstats');
  [[t.ec, t.ec === 1 ? 'episode' : 'episodes'],
   [t.sc, t.sc === 1 ? 'show' : 'shows']]
    .forEach(([n, l]) => { const x = el('span'); x.appendChild(el('b', null, String(n))); x.append(' ' + l); stats.appendChild(x); });
  head.appendChild(stats);

  const chips = el('div', 'dchips');
  if (t.spec) chips.appendChild(el('span', 'tag warn', 'only one show uses this'));
  if (t.junk) chips.appendChild(el('span', 'tag warn', 'junk-drawer suspect'));
  (t.rel || []).forEach(r => {
    const th = state.data.themes[r];
    if (th) { const x = el('span', 'tag'); x.textContent = th.name; x.title = 'Related show-level theme'; chips.appendChild(x); }
  });
  if (chips.childElementCount) head.appendChild(chips);
  view.appendChild(head);

  const users = showsUsing(gi);
  const sec = el('div', 'sec');
  sec.appendChild(el('h2', null, 'Across the catalog'));
  sec.appendChild(el('span', 'count', String(users.length)));
  view.appendChild(sec);

  if (!users.length) { view.appendChild(el('p', 'empty', 'No show uses this theme yet.')); return; }

  const grid = el('div', 'grid');
  users.forEach(({ s: sh, count }) => {
    const c = el('button', 'card');
    c.onclick = () => go('#/show/' + encodeURIComponent(sh.slug));
    const a = el('div', 'card-art');
    if (sh.art) a.style.backgroundImage = `url("${art(sh.art)}")`;
    else a.appendChild(el('span', null, initials(sh.title)));
    c.appendChild(a);
    c.appendChild(el('div', 'card-title', sh.title));
    c.appendChild(el('div', 'card-sub', sh.network || sh.author || ''));
    const foot = el('div', 'card-foot');
    foot.appendChild(el('span', 'tag model', `${count} episode${count > 1 ? 's' : ''}`));
    c.appendChild(foot);
    grid.appendChild(c);
  });
  view.appendChild(grid);

  const sec2 = el('div', 'sec');
  sec2.appendChild(el('h2', null, 'Episodes'));
  view.appendChild(sec2);
  const list = el('div', 'eps');
  let n = 0;
  for (const { s: sh } of users) {
    for (const e of sh.eps) {
      if (e[5] !== gi && !(e[7] || []).some(([x]) => x === gi)) continue;
      if (n++ >= 200) break;
      const row = el('div', 'ep');
      row.appendChild(el('span', 'ep-date', fmtDate(e[1])));
      const body = el('span', 'ep-t');
      const b = el('span', 'ep-arc ep-theme', sh.title);
      b.onclick = ev => { ev.stopPropagation(); go('#/show/' + encodeURIComponent(sh.slug)); };
      body.appendChild(b);
      body.append(e[0]);
      row.appendChild(body);
      const tag = el('span', 'ep-tags');
      if (e[5] !== gi) tag.appendChild(el('span', 'tag sec', 'secondary'));
      row.appendChild(tag);
      list.appendChild(row);
    }
    if (n >= 200) break;
  }
  view.appendChild(list);
  if (n >= 200) view.appendChild(el('p', 'trim', 'Showing the first 200 episodes.'));
}

/* ---------- show detail ---------- */
function renderDetail() {
  const s = state.data.shows.find(x => x.slug === state.slug);
  if (!s) return go('#/browse');
  const r = rec(s.slug);
  const view = $('#view');
  view.replaceChildren();
  $('#crumb').textContent = '';

  const back = el('button', 'back', '← Catalog');
  back.onclick = () => go('#/browse');
  view.appendChild(back);

  const head = el('div', 'dhead');
  const a = el('div', 'dart');
  if (s.art) a.style.backgroundImage = `url("${art(s.art)}")`;
  else a.appendChild(el('span', null, initials(s.title)));
  head.appendChild(a);
  const meta = el('div', 'dmeta');
  if (s.category) meta.appendChild(el('div', 'dcat', s.category));
  meta.appendChild(el('h1', 'dtitle', s.title));
  meta.appendChild(el('div', 'dauthor', [s.author, s.years].filter(Boolean).join(' · ')));
  if (s.desc) meta.appendChild(el('p', 'ddesc', s.desc));
  const pl = (n, one, many) => (n === 1 ? one : many);
  const stats = el('div', 'dstats');
  [[s.nEps, pl(s.nEps, 'episode', 'episodes')],
   [s.span, pl(s.span, 'month of publishing', 'months of publishing')],
   [s.seasons, pl(s.seasons, 'season tag', 'season tags')],
   [s.arcs.length, pl(s.arcs.length, 'arc', 'arcs')]]
    .forEach(([n, l]) => { const x = el('span'); x.appendChild(el('b', null, String(n))); x.append(' ' + l); stats.appendChild(x); });
  meta.appendChild(stats);
  const chips = el('div', 'dchips');
  s.patterns.forEach(p => { const m = state.data.patterns[p];
    if (m) { const t = el('span', 'tag' + (m.family === 'structural' ? ' struct' : ''), m.label); t.title = m.hint; chips.appendChild(t); } });
  (s.themes || []).forEach(t => { const th = state.data.themes[t]; if (th) chips.appendChild(el('span', 'tag', th.name)); });
  if (chips.childElementCount) meta.appendChild(chips);
  head.appendChild(meta);
  view.appendChild(head);

  if (s.small) {
    const box = el('div', 'feednote');
    box.appendChild(el('strong', null, s.small.label));
    box.appendChild(el('span', null, ' — ' + s.small.why + '.'));
    if (s.access && s.access !== 'free-public') box.appendChild(el('span', 'tag warn', s.access.replace(/-/g, ' ')));
    box.appendChild(el('p', null,
      'The fetch takes up to 800 episodes, so this is what the feed served — not a truncated download. '
      + 'A subscriber’s own feed URL would carry the full archive.'));
    view.appendChild(box);
  }

  if (s.arcs.length) {
    const sec = el('div', 'sec');
    sec.appendChild(el('h2', null, 'Story arcs'));
    sec.appendChild(el('span', 'count', String(s.arcs.length)));
    view.appendChild(sec);
    const wrap = el('div', 'arcs');
    s.arcs.forEach((arc, i) => wrap.appendChild(arcCard(s, arc, i, r)));
    view.appendChild(wrap);
  }

  const mine = showThemes(s);
  if (mine.length) {
    const sec = el('div', 'sec');
    sec.appendChild(el('h2', null, 'Themes'));
    sec.appendChild(el('span', 'count', String(mine.length)));
    const ag = s.themes_meta && s.themes_meta.agreement;
    if (ag && ag.primaryAgreement != null) {
      sec.appendChild(el('div', 'spacer'));
      const x = el('span', 'agree', `${Math.round(ag.primaryAgreement * 100)}% agreement across two passes`);
      x.title = 'Two independent labelling runs; where they disagree the theme boundary is fuzzy.';
      sec.appendChild(x);
    }
    view.appendChild(sec);
    if (s.auditFlags && s.auditFlags.length) {
      const w = el('div', 'feednote');
      w.appendChild(el('strong', null, 'Audit flagged this show'));
      s.auditFlags.forEach(f => w.appendChild(el('p', null, f)));
      view.appendChild(w);
    }

    /* The theme filter. Most shows have no arcs at all, so on those screens this is the
       only structure there is for digging through hundreds of episodes. */
    const bar = el('div', 'tfilter');
    const chip = (label, n, on, fn) => {
      const b = el('button', 'tchip' + (on ? ' on' : ''));
      b.appendChild(el('span', null, label));
      if (n != null) b.appendChild(el('span', 'tchip-n', String(n)));
      b.onclick = fn;
      return b;
    };
    bar.appendChild(chip('All episodes', s.eps.length, state.theme == null,
      () => { state.theme = null; state.arc = null; renderDetail(); }));
    mine.forEach(t => bar.appendChild(chip(t.n, t.count, state.theme === t.gi,
      () => { state.theme = state.theme === t.gi ? null : t.gi; state.arc = null; renderDetail(); })));
    view.appendChild(bar);

    const tw = el('div', 'arcs');
    mine.forEach(t => tw.appendChild(themeCard(s, t, t.gi, r)));
    view.appendChild(tw);
  }

  if (!s.arcs.length && !(s.themesUsed || []).length) {
    const g = s.small ? null : state.data.noArcGroups[s.group];
    const sec = el('div', 'sec');
    sec.appendChild(el('h2', null, 'No arcs detected'));
    if (g) sec.appendChild(el('span', 'count', g.label));
    else if (s.small) sec.appendChild(el('span', 'count', 'not enough feed to tell'));
    view.appendChild(sec);
    if (g) view.appendChild(el('p', 'ddesc', g.hint));
  }

  const sv = el('div', 'showverdict');
  sv.appendChild(el('p', null, (s.arcs.length || (s.themesUsed || []).length)
    ? 'Or judge the whole show at once:'
    : 'Is that right — does this show genuinely have no multi-part stories?'));
  const noneBtn = el('button', r.show ? 'on' : '', r.show ? '✓ Confirmed: no arcs here' : 'No arcs here');
  noneBtn.onclick = async () => { await saveVerdict({ slug: s.slug, kind: 'show', verdict: r.show ? 'clear' : 'none' }); render(); };
  sv.appendChild(noneBtn);
  view.appendChild(sv);

  const esec = el('div', 'sec');
  esec.appendChild(el('h2', null, 'Episodes'));
  // A confidence filter narrows the episode list too, so picking "Low" and opening a show
  // lands you on exactly the rows worth a second look.
  const shown = state.arc != null ? s.eps.filter(e => e[4] === state.arc)
              : state.theme != null ? s.eps.filter(e => e[5] === state.theme)
              : state.f.conf ? s.eps.filter(e => e[6] === state.f.conf) : s.eps;
  esec.appendChild(el('span', 'count', String(shown.length)));
  esec.appendChild(el('div', 'spacer'));
  if (state.arc != null || state.theme != null || state.f.conf) {
    const label = state.arc != null ? s.arcs[state.arc].n
                : state.theme != null ? (themeAt(state.theme) || {}).n
                : ({ l: 'Low', m: 'Medium', h: 'High' })[state.f.conf] + ' confidence';
    const f = el('button', 'ep-filter', `Showing: ${label}  ✕`);
    f.onclick = () => {
      state.arc = state.theme = null;
      if (!(state.arc != null || state.theme != null)) state.f.conf = null;
      render();
    };
    esec.appendChild(f);
  }
  view.appendChild(esec);

  const list = el('div', 'eps');
  const CONF = { l: 'low', m: 'med', h: 'high' };
  shown.forEach(e => {
    const row = el('div', 'ep' + (e[4] === -1 && e[5] === -1 ? ' off' : ''));
    row.appendChild(el('span', 'ep-date', fmtDate(e[1])));
    const body = el('span', 'ep-t');
    // An arc badge and a theme badge can both appear: the two indexes are orthogonal,
    // and an episode inside an arc still has a subject.
    if (e[4] !== -1 && state.arc == null) body.appendChild(el('span', 'ep-arc', s.arcs[e[4]].n));
    if (e[5] != null && e[5] !== -1 && state.theme == null) {
      const t = themeAt(e[5]);
      if (t) {
        const b = el('span', 'ep-arc ep-theme', t.n);
        b.onclick = ev => { ev.stopPropagation(); go('#/theme/' + encodeURIComponent(t.s)); };
        b.title = 'See this theme across every show';
        body.appendChild(b);
      }
    }
    body.append(e[0]);
    row.appendChild(body);

    const tag = el('span', 'ep-tags');
    // Confidence rides on each application, so a shaky secondary shows its own badge
    // instead of hiding behind a strong primary.
    if (e[6] && e[6] !== 'h')
      tag.appendChild(el('span', 'tag conf-' + e[6], CONF[e[6]]));
    (e[7] || []).forEach(([gi, c]) => {
      const t = themeAt(gi);
      if (!t) return;
      const b = el('span', 'tag sec' + (c && c !== 'h' ? ' conf-' + c : ''), t.n);
      b.title = `secondary · ${CONF[c] || c} confidence`;
      b.onclick = ev => { ev.stopPropagation(); go('#/theme/' + encodeURIComponent(t.s)); };
      tag.appendChild(b);
    });
    if (e[3]) tag.appendChild(el('span', 'tag', e[3]));
    else if (e[2] != null) tag.appendChild(el('span', 'tag', 'S' + e[2]));
    row.appendChild(tag);
    list.appendChild(row);
  });
  view.appendChild(list);
  if (state.arc == null && state.theme == null && s.eps.length < s.nEps)
    view.appendChild(el('p', 'trim', `Showing ${s.eps.length} of ${s.nEps} episodes — every grouped episode, plus a sample of the rest.`));
}

function verdictRow(cur, onPick) {
  const vs = el('div', 'verdicts');
  [['right', '✓'], ['wrong', '✗'], ['unsure', '?']].forEach(([v, glyph]) => {
    const b = el('button', 'v' + (cur === v ? ' on-' + v : ''), glyph);
    b.title = v;
    b.onclick = e => { e.stopPropagation(); onPick(cur === v ? 'clear' : v); };
    vs.appendChild(b);
  });
  return vs;
}

function arcCard(s, arc, i, r) {
  const card = el('div', 'arc' + (state.arc === i ? ' active' : ''));
  const top = el('div', 'arc-top');
  const pat = state.data.patterns[arc.p];
  top.appendChild(el('span', 'tag' + (pat && pat.family === 'structural' ? ' struct' : ''), pat ? pat.label : arc.p));
  if (arc.s != null) top.appendChild(el('span', 'arc-season', 'S' + arc.s));
  card.appendChild(top);
  const name = el('div', 'arc-name', arc.n);
  name.onclick = () => { state.arc = state.arc === i ? null : i; state.theme = null; renderDetail(); };
  card.appendChild(name);
  const parts = el('div', 'arc-parts', `${arc.c} episodes`);
  parts.onclick = name.onclick;
  card.appendChild(parts);
  card.appendChild(verdictRow(arcVerdict(s.slug, i), async v => {
    await saveVerdict({ slug: s.slug, kind: 'arc', index: i, verdict: v, name: arc.n, count: arc.c });
    render();
  }));
  return card;
}

function themeCard(s, t, i, r) {
  const card = el('div', 'arc theme' + (state.theme === i ? ' active' : ''));
  const top = el('div', 'arc-top');
  top.appendChild(el('span', 'tag model', `${t.count} here`));
  if (t.sc > 1) {
    const x = el('span', 'tag', `${t.sc} shows`);
    x.title = 'How many shows use this theme — this is what cross-show discovery runs on';
    top.appendChild(x);
  }
  if (t.spec) { const x = el('span', 'tag warn', 'only this show'); x.title = 'Used by one show. Kept, flagged for a later merge pass.'; top.appendChild(x); }
  if (t.junk) { const x = el('span', 'tag warn', 'junk drawer?'); x.title = 'Definition reads as a catch-all'; top.appendChild(x); }
  card.appendChild(top);
  const name = el('div', 'arc-name', t.n);
  name.onclick = () => { state.theme = state.theme === i ? null : i; state.arc = null; renderDetail(); };
  card.appendChild(name);
  const def = el('div', 'theme-def', t.d);
  def.onclick = name.onclick;
  card.appendChild(def);
  card.appendChild(verdictRow(themeVerdict(s.slug, t.s), async v => {
    await saveVerdict({ slug: s.slug, kind: 'theme', theme: t.s, verdict: v, name: t.n });
    render();
  }));
  return card;
}

/* ---------- system ----------
   Structured as two timelines people conflate: what happens on the phone when you
   open a show (milliseconds), and what happens on this machine to produce the data
   it reads (occasional, manual). Plus the rule that decides between them. */

/* ---- flowchart renderer ----
   Small on purpose: nodes carry absolute coordinates, edges are routed as either a
   vertical elbow or a straight horizontal side-exit. Enough for a decision tree,
   and it means no diagram library. Colours come from CSS vars so both themes work. */
const SVGNS = 'http://www.w3.org/2000/svg';
const svgEl = (t, attrs) => {
  const n = document.createElementNS(SVGNS, t);
  for (const k in attrs) n.setAttribute(k, attrs[k]);
  return n;
};

function flowchart(spec) {
  const svg = svgEl('svg', {
    viewBox: `0 0 ${spec.w} ${spec.h}`, class: 'chart',
    role: 'img', 'aria-label': spec.alt || 'flow diagram',
  });
  const defs = svgEl('defs');
  ['arrow', 'arrow-dim'].forEach(id => {
    const m = svgEl('marker', { id, viewBox: '0 0 10 10', refX: '9', refY: '5',
      markerWidth: '6', markerHeight: '6', orient: 'auto-start-reverse' });
    m.appendChild(svgEl('path', { d: 'M0,0 L10,5 L0,10 z', class: id }));
    defs.appendChild(m);
  });
  svg.appendChild(defs);

  const N = {};
  spec.nodes.forEach(n => { N[n.id] = n; });
  const left = n => n.cx - n.w / 2, right = n => n.cx + n.w / 2;
  const bottom = n => n.y + n.h, midY = n => n.y + n.h / 2;

  // edges first so boxes paint over the line ends
  spec.edges.forEach(e => {
    const a = N[e.from], b = N[e.to];
    const g = svgEl('g', { class: 'edge' + (e.dim ? ' dim' : '') });
    let d, lx, ly;
    if (e.side) {
      d = `M ${right(a)} ${midY(a)} H ${left(b)}`;
      lx = (right(a) + left(b)) / 2; ly = midY(a) - 8;
    } else if (Math.abs(a.cx - b.cx) < 1) {
      d = `M ${a.cx} ${bottom(a)} V ${b.y}`;
      lx = a.cx + 12; ly = (bottom(a) + b.y) / 2 + 4;
    } else {
      const my = bottom(a) + Math.max(16, (b.y - bottom(a)) / 2);
      d = `M ${a.cx} ${bottom(a)} V ${my} H ${b.cx} V ${b.y}`;
      // Sit the label over its own horizontal run, not at the split — otherwise the
      // yes and no of one decision collide.
      lx = (a.cx + b.cx) / 2; ly = my - 7;
    }
    g.appendChild(svgEl('path', { d, class: 'link', 'marker-end': `url(#${e.dim ? 'arrow-dim' : 'arrow'})` }));
    if (e.label) {
      const t = svgEl('text', { x: lx, y: ly, class: 'elabel',
        'text-anchor': (e.side || Math.abs(a.cx - b.cx) > 1) ? 'middle' : 'start' });
      t.textContent = e.label;
      g.appendChild(t);
    }
    svg.appendChild(g);
  });

  spec.nodes.forEach(n => {
    const g = svgEl('g', { class: 'node-g ' + n.kind });
    if (n.kind === 'dec') {
      g.appendChild(svgEl('polygon', { class: 'shape',
        points: `${n.cx},${n.y} ${right(n)},${midY(n)} ${n.cx},${bottom(n)} ${left(n)},${midY(n)}` }));
    } else {
      g.appendChild(svgEl('rect', { class: 'shape', x: left(n), y: n.y, width: n.w, height: n.h,
        rx: n.kind === 'start' ? n.h / 2 : 10 }));
    }
    const lines = n.lines || [n.label];
    const lh = 15, startY = midY(n) - ((lines.length - 1) * lh) / 2 + 4;
    lines.forEach((ln, i) => {
      const mono = ln.startsWith('`');
      const t = svgEl('text', { x: n.cx, y: startY + i * lh, 'text-anchor': 'middle',
        class: 'nlabel' + (mono ? ' mono' : '') });
      t.textContent = mono ? ln.replace(/`/g, '') : ln;
      g.appendChild(t);
    });
    svg.appendChild(g);
  });
  return svg;
}

/* What happens to one show — the only path that matters for understanding the store. */
const CHART_INTAKE = {
  w: 1080, h: 545, alt: 'How one show ends up with arcs, themes, or nothing',
  nodes: [
    { id: 'feed', cx: 250, y: 12, w: 260, h: 44, kind: 'start', label: "One show's RSS feed" },
    { id: 'd1', cx: 250, y: 82, w: 300, h: 76, kind: 'dec', lines: ['Does the feed publish', 'enough of the show?'] },
    { id: 'oLabel', cx: 760, y: 94, w: 350, h: 64, kind: 'warn',
      lines: ['Feed labelled, nothing grouped', '`TAL — 15 of ~892 · WeCrashed — 1`'] },
    { id: 'd2', cx: 250, y: 196, w: 310, h: 80, kind: 'dec', lines: ['Do episode titles carry', 'a counter or a pattern?'] },
    { id: 'oArcs', cx: 760, y: 210, w: 350, h: 64, kind: 'ok',
      lines: ['ARCS stored', '`Am. History Tellers 85 · Radiolab 5`'] },
    { id: 'd3', cx: 250, y: 314, w: 310, h: 86, kind: 'dec', lines: ['An anthology — many', 'standalone episodes?'] },
    { id: 'oThemes', cx: 760, y: 330, w: 350, h: 64, kind: 'model',
      lines: ['THEMES proposed by the model', '`Swindled — 14 over 153 stories`'] },
    { id: 'oNone', cx: 250, y: 452, w: 320, h: 62, kind: 'muted',
      lines: ['Nothing stored — correct', '`Normal Gossip — a new guest weekly`'] },
  ],
  edges: [
    { from: 'feed', to: 'd1' },
    { from: 'd1', to: 'oLabel', side: true, label: 'no', dim: true },
    { from: 'd1', to: 'd2', label: 'yes' },
    { from: 'd2', to: 'oArcs', side: true, label: 'yes' },
    { from: 'd2', to: 'd3', label: 'no' },
    { from: 'd3', to: 'oThemes', side: true, label: 'yes' },
    { from: 'd3', to: 'oNone', label: 'no', dim: true },
  ],
};

/* The four shows you keep asking about, and what the store actually holds for each. */
const EXAMPLES = [
  { show: 'American History Tellers', eps: '484 episodes', holds: '85 arcs', kind: 'ok',
    why: 'Titles are “Name | Episode title | 3”. The counter is right there, so regex groups it and no model is involved.' },
  { show: 'Radiolab', eps: '659 episodes', holds: '5 arcs', kind: 'ok',
    why: 'Five genuinely named series — Border Trilogy, The Other Latif. The other 636 episodes are standalone and would need themes, which have not been run yet.' },
  { show: 'Swindled', eps: '147 episodes', holds: '14 themes over 153 stories', kind: 'model',
    why: 'Zero arcs — every episode is a different scandal. But the titles name the subject (“The Descent (OceanGate)”), so a model could group them by the kind of story.' },
  { show: 'This American Life', eps: '15 public of ~892', holds: 'nothing, and a label', kind: 'warn',
    why: 'The feed publishes a rolling window. There is nothing to group because 98% of the show is not public. A TAL+ subscriber’s own feed would have it all.' },
  { show: 'WeCrashed', eps: '1 public episode', holds: 'nothing, and a label', kind: 'warn',
    why: 'The feed carries episode one plus an item literally titled “Where to find Episodes 2-7”. The archive is behind a subscription.' },
  { show: 'Normal Gossip', eps: '107 episodes', holds: 'nothing', kind: 'muted',
    why: 'A different guest every week with a deliberately cryptic title. Finding nothing here is the right answer, not a failure.' },
];

/* Separate on purpose: this runs on EVERY render, not once per open. */
const CHART_SHELF = {
  w: 940, h: 500, alt: 'How the app decides whether to show the story arcs shelf',
  nodes: [
    { id: 'eps', cx: 250, y: 12, w: 280, h: 42, kind: 'start', label: 'Episodes are on screen' },
    { id: 'derive', cx: 250, y: 78, w: 360, h: 56, kind: 'proc',
      lines: ['`ArcDerivation.groupIntoArcs(episodes)`', 'every render — nothing cached'] },
    { id: 'dA', cx: 250, y: 168, w: 230, h: 72, kind: 'dec', lines: ['Any arcs', 'came back?'] },
    { id: 'hidden', cx: 680, y: 181, w: 250, h: 46, kind: 'muted', label: 'Shelf hidden entirely' },
    { id: 'shelf', cx: 250, y: 274, w: 260, h: 48, kind: 'ok', label: 'Story arcs shelf shows' },
    { id: 'dB', cx: 250, y: 348, w: 230, h: 72, kind: 'dec', lines: ['You tap', 'an arc card?'] },
    { id: 'full', cx: 680, y: 361, w: 250, h: 46, kind: 'muted', label: 'Full episode list' },
    { id: 'filt', cx: 250, y: 446, w: 330, h: 48, kind: 'ok', label: 'List filters + “Showing: … ✕”' },
  ],
  edges: [
    { from: 'eps', to: 'derive' },
    { from: 'derive', to: 'dA' },
    { from: 'dA', to: 'hidden', side: true, label: 'no', dim: true },
    { from: 'dA', to: 'shelf', label: 'yes' },
    { from: 'shelf', to: 'dB' },
    { from: 'dB', to: 'full', side: true, label: 'no', dim: true },
    { from: 'dB', to: 'filt', label: 'yes' },
  ],
};

const LADDER = [
  { t: 'A grouping you approved', st: 'planned', src: 'shipped data',
    d: 'Curated in this workbench and exported. Beats everything below it, including a detector that disagrees.' },
  { t: 'A model-proposed theme', st: 'planned', src: 'shipped data',
    d: 'For anthologies where no arc exists. Ships in the same file, marked as proposed rather than confirmed.' },
  { t: 'On-device regex', st: 'built', src: 'computed on the phone',
    d: 'What runs today for everything — and the only thing that will ever run for a feed you added yourself, because it is not in the catalog.' },
  { t: 'Nothing', st: 'built', src: '—',
    d: 'No arcs derived, so the shelf is hidden. This is a correct answer for most interview and news shows.' },
];

const SYNCS = [
  { what: 'Episodes', from: "the show's own RSS", when: 'every time you open it, in the background',
    off: 'the last saved copy renders', st: 'built' },
  { what: 'Show catalog', from: 'catalog.json bundled in the app', when: 'with each app release',
    off: 'always available', st: 'built' },
  { what: 'Arcs & themes', from: 'bundled snapshot, then a versioned file on a static host',
    when: 'version check on launch; one download when it changes', off: 'the bundled snapshot stands', st: 'planned' },
  { what: 'Feed corpus', from: 'scripts/fetch-atlas-feeds.py', when: 'manual, resumable, skips what it has',
    off: 'n/a — this machine only', st: 'built' },
  { what: 'Detection', from: 'approaches.py over the corpus', when: 'manual, after a rule change',
    off: 'n/a', st: 'built' },
  { what: 'Model themes', from: 'episode-theme-workflow.mjs', when: 'manual, one show at a time',
    off: 'n/a', st: 'partial' },
];

const PIPELINE = [
  { head: 'Sources', nodes: [
    { t: '315 RSS snapshots', s: 'curation/feeds/', st: 'built', d: 'Titles, dates, season tags. No descriptions.' },
    { t: 'Catalog metadata', s: 'catalog.json', st: 'built', d: '315 shows — art, network, themes. Joined on slugify(title).' },
  ]},
  { head: 'Producers', nodes: [
    { t: 'Regex detector', s: 'approaches.py · A8-cascade', st: 'built', d: '1,583 arcs across 221 shows, from 10 title patterns + 7 structural rules.' },
    { t: 'Model proposer', s: 'episode-theme-workflow.mjs', st: 'partial', d: 'Themes anthologies that have no arcs. Swindled done; 101 large feeds to go.' },
    { t: 'You', s: 'this workbench', st: 'built', d: 'The only source that can add what no algorithm finds — and the only one that wins.' },
  ]},
  { head: 'Store', nodes: [
    { t: 'SQLite', s: 'arcs · themes · verdicts · edit log', st: 'planned', d: 'Durable ids matched across re-detection by member overlap, so a regex change cannot renumber your decisions.' },
  ]},
  { head: 'Delivery', nodes: [
    { t: 'Local API', s: 'serve-catalog.py :8420', st: 'built', d: 'Read and write. Localhost by default. Never public.' },
    { t: 'Export', s: 'manifest + versioned JSON', st: 'planned', d: '198 KB gzipped. Immutable filename, so it caches forever.' },
    { t: 'Static host', s: 'Cloudflare Pages', st: 'planned', d: 'Free tier. No server, no auth, nothing to keep running.' },
    { t: 'iOS app', s: 'IWantUrPod/Resources/', st: 'planned', d: 'Ships a snapshot so a cold install works offline, then refreshes when reachable.' },
  ]},
];
const LAYERS = [
  { t: 'Authored', c: 'authored', s: 'you', d: 'Precious. Never overwritten by anything below.' },
  { t: 'Proposed', c: 'proposed', s: 'the model', d: 'Regenerable. Thrown away and redone freely.' },
  { t: 'Detected', c: 'detected', s: 'regex', d: 'Regenerable. Good at named series and counters.' },
];

function node(n) {
  const b = el('div', 'node ' + n.st);
  const h = el('div', 'node-h');
  h.appendChild(el('span', 'node-t', n.t));
  h.appendChild(el('span', 'dot ' + n.st));
  b.appendChild(h);
  b.appendChild(el('code', 'node-s', n.s));
  b.appendChild(el('p', 'node-d', n.d));
  return b;
}

const SYS_SECTIONS = [
  ['holds', 'What the store holds'],
  ['intake', 'How a show gets in'],
  ['shows', 'Six real shows'],
  ['out', 'How it reaches the app'],
  ['sync', 'What syncs, and when'],
];

function sysHead(id, title, sub) {
  const wrap = el('section', 'sys');
  wrap.id = 'sys-' + id;
  const sec = el('div', 'sec');
  sec.appendChild(el('h2', null, title));
  wrap.appendChild(sec);
  if (sub) wrap.appendChild(el('p', 'sys-sub', sub));
  return wrap;
}

function renderSystem() {
  const { items, judged } = totals();
  $('#crumb').textContent = '';
  const view = $('#view');
  view.replaceChildren();

  view.appendChild(el('h1', 'dtitle', 'How this works'));
  view.appendChild(el('p', 'ddesc',
    'A catalog of story arcs and themes, built show by show on this machine and exported to a file '
    + 'the app reads. Regex proposes, a model proposes where regex cannot, and you decide. '
    + `${items.toLocaleString()} groupings exist so far; ${judged === 1 ? '1 has' : judged + ' have'} a verdict.`));

  // Run-level numbers only. The per-object badges and facets are the point; this is a
  // footnote that says whether the last theming run finished and how clean it came out.
  const r = state.data.epRun;
  if (r) {
    const box = el('div', 'runsum');
    box.appendChild(el('h2', null, 'Last episode-theming run'));
    const g = el('div', 'dstats');
    const stat = (n, l) => { const x = el('span'); x.appendChild(el('b', null, String(n))); x.append(' ' + l); g.appendChild(x); };
    stat((r.episodes || 0).toLocaleString(), 'episodes labelled');
    stat(r.shows || 0, 'shows');
    stat(r.vocab || 0, 'themes in the shared vocabulary');
    if (r.agreement && r.agreement.primaryAgreement != null)
      stat(Math.round(r.agreement.primaryAgreement * 100) + '%', 'two-run agreement');
    box.appendChild(g);
    const flags = el('div', 'dchips');
    if (r.unassigned) flags.appendChild(el('span', 'tag warn', `${r.unassigned.toLocaleString()} episodes unassigned`));
    if (r.showSpecific) flags.appendChild(el('span', 'tag', `${r.showSpecific} themes used by one show`));
    if (r.junk) flags.appendChild(el('span', 'tag warn', `${r.junk} junk-drawer suspects`));
    if (r.auditFlags) flags.appendChild(el('span', 'tag warn', `${r.auditFlags} catalog audit flags`));
    if (flags.childElementCount) box.appendChild(flags);
    view.appendChild(box);
  }

  const legend = el('div', 'legend2');
  [['built', 'built and running'], ['partial', 'partly built'], ['planned', 'not built yet']]
    .forEach(([k, label]) => { const s = el('span', 'lg'); s.appendChild(el('span', 'dot ' + k)); s.append(label); legend.appendChild(s); });
  const jump = el('nav', 'jump');
  SYS_SECTIONS.forEach(([id, label]) => {
    const a = el('a', null, label);
    a.href = '#sys-' + id;
    a.onclick = e => { e.preventDefault(); $('#sys-' + id).scrollIntoView({ behavior: 'smooth', block: 'start' }); };
    jump.appendChild(a);
  });
  legend.appendChild(jump);
  view.appendChild(legend);

  /* 1 — the data model */
  const s1 = sysHead('holds', 'What the store holds',
    'One row per show, and under it the groupings found for that show. A grouping is either an '
    + 'ARC (a run of episodes that is one story) or a THEME (a kind of story, for shows that have '
    + 'no arcs). Both point at episodes by guid. Your verdict sits beside them.');
  const tree = el('div', 'tree');
  const treeRows = [
    { d: 0, t: 'SHOW', n: '315', k: 'ok', s: 'joined to catalog.json on slugify(title)',
      d2: 'Swindled, Radiolab, This American Life…' },
    { d: 1, t: 'ARC', n: '1,583', k: 'ok', s: 'name · season · the episodes in it',
      d2: '“Border Trilogy” — 6 episodes of Radiolab' },
    { d: 1, t: 'THEME', n: '14', k: 'model', s: 'name · definition · parent · the episodes in it',
      d2: '“Unsafe Products & Corporate Cover-Ups” — 20 Swindled episodes' },
    { d: 2, t: 'parent theme', n: '30', k: 'plain', s: 'the catalog-wide themes already in the app',
      d2: 'that one rolls up to “The Institutional Cover-Up”' },
    { d: 1, t: 'YOUR VERDICT', n: '1', k: 'ok', s: 'right · wrong · unsure · no-arcs-here',
      d2: 'beats any detector that disagrees' },
  ];
  treeRows.forEach(r => {
    const row = el('div', 'trow d' + r.d + ' ' + r.k);
    const h = el('div', 'node-h');
    const left = el('span');
    left.appendChild(el('span', 'trow-t', r.t));
    left.appendChild(el('span', 'trow-n', '×' + r.n));
    h.appendChild(left);
    row.appendChild(h);
    row.appendChild(el('code', 'node-s', r.s));
    row.appendChild(el('p', 'node-d', r.d2));
    tree.appendChild(row);
  });
  s1.appendChild(tree);
  s1.appendChild(el('p', 'flow-note',
    'Everything above lives in one SQLite file on this machine. Nothing about it is live and '
    + 'nothing about it is on the phone yet — the phone still derives arcs itself, which is the '
    + 'gap the store closes.'));
  view.appendChild(s1);

  /* 2 — intake */
  const s2i = sysHead('intake', 'How a show gets in',
    'Each show takes exactly one path through this. Which path it takes is why Swindled has themes, '
    + 'Radiolab has arcs, and This American Life has neither.');
  s2i.appendChild(flowchart(CHART_INTAKE));
  s2i.appendChild(el('p', 'flow-note',
    'Regex runs first because it is free and exact. The model is only asked about shows regex '
    + 'could not group — which is why Swindled got themes and American History Tellers never needed '
    + 'them. Whatever comes out, you rule on it, and your ruling is what ships.'));

  s2i.appendChild(el('h3', 'sub-h', 'When two of them disagree about the same show'));
  const stack = el('div', 'stack');
  LAYERS.forEach((l, i) => {
    const row = el('div', 'layer ' + l.c);
    row.appendChild(el('span', 'layer-rank', String(i + 1)));
    const body = el('div');
    body.appendChild(el('div', 'node-t', l.t));
    body.appendChild(el('code', 'node-s', l.s));
    body.appendChild(el('p', 'node-d', l.d));
    row.appendChild(body);
    stack.appendChild(row);
  });
  s2i.appendChild(stack);
  s2i.appendChild(el('p', 'flow-note',
    'Re-running a detector or the model can only add candidates. Neither can change a call you '
    + 'already made, because groupings are matched across re-runs by which episodes they contain, '
    + 'not by their position in a list.'));
  view.appendChild(s2i);

  /* 3 — worked examples */
  const s3e = sysHead('shows', 'Six real shows',
    'The same six paths, with the actual numbers from the corpus.');
  const exw = el('div', 'tablewrap');
  const ext = el('table', 'synct exts');
  const eth = el('thead'); const ehr = el('tr');
  ['Show', 'In the feed', 'What the store holds', 'Why'].forEach(h => ehr.appendChild(el('th', null, h)));
  eth.appendChild(ehr); ext.appendChild(eth);
  const etb = el('tbody');
  EXAMPLES.forEach(x => {
    const tr = el('tr');
    tr.appendChild(el('td', 'sync-what', x.show));
    tr.appendChild(el('td', 'dim', x.eps));
    const h = el('td');
    h.appendChild(el('span', 'tag ' + (x.kind === 'ok' ? 'on' : x.kind === 'model' ? 'model' : x.kind === 'warn' ? 'warn' : 'none'), x.holds));
    tr.appendChild(h);
    tr.appendChild(el('td', null, x.why));
    etb.appendChild(tr);
  });
  ext.appendChild(etb); exw.appendChild(ext); s3e.appendChild(exw);
  view.appendChild(s3e);

  /* 4 — out to the app */
  const s2 = sysHead('out', 'How it reaches the app',
    'The store is exported to a file the app reads. When that ships, the phone will ask these in '
    + 'order and stop at the first answer — today only the third rung exists, which is why the '
    + 'phone still computes arcs itself on every render.');
  const ladder = el('div', 'ladder');
  LADDER.forEach((l, i) => {
    const row = el('div', 'rung ' + l.st);
    row.appendChild(el('span', 'rung-n', String(i + 1)));
    const body = el('div');
    const h = el('div', 'node-h');
    h.appendChild(el('span', 'node-t', l.t));
    h.appendChild(el('span', 'dot ' + l.st));
    body.appendChild(h);
    body.appendChild(el('code', 'node-s', l.src));
    body.appendChild(el('p', 'node-d', l.d));
    row.appendChild(body);
    ladder.appendChild(row);
  });
  s2.appendChild(ladder);

  const two = el('div', 'twocol');
  [{ t: 'A catalog show', d: 'Radiolab, Swindled, the other 313. Arcs and themes are computed here, curated by you, and shipped as data. The phone reads rather than works.' },
   { t: 'A feed you added yourself', d: 'A premium or private feed — a TAL+ URL. Never in the catalog, so there is no data to ship and rungs 1 and 2 are always empty. It falls to on-device regex, which is why that detector still has to be good.' }]
    .forEach(x => {
      const c = el('div', 'node built');
      const h = el('div', 'node-h');
      h.appendChild(el('span', 'node-t', x.t));
      h.appendChild(el('span', 'dot built'));
      c.appendChild(h);
      c.appendChild(el('p', 'node-d', x.d));
      two.appendChild(c);
    });
  s2.appendChild(two);

  s2.appendChild(el('h3', 'sub-h', 'What the phone does today, with no store'));
  s2.appendChild(flowchart(CHART_SHELF));
  s2.appendChild(el('p', 'flow-note',
    'Arcs are a computed property in the app, so this re-runs every time the view draws — nothing '
    + 'cached, nothing looked up. Once the export ships, rungs 1 and 2 answer first and this '
    + 'becomes the fallback rather than the whole story.'));
  view.appendChild(s2);


  /* 4 — sync */
  const s4 = sysHead('sync', 'What syncs, and when',
    'Nothing here is live. Every row is either bundled with the app, fetched per show open, or run by hand.');
  const tw = el('div', 'tablewrap');
  const t = el('table', 'synct');
  const thead = el('thead');
  const hr = el('tr');
  ['', 'Comes from', 'Refreshed', 'Offline'].forEach(h => hr.appendChild(el('th', null, h)));
  thead.appendChild(hr); t.appendChild(thead);
  const tb = el('tbody');
  SYNCS.forEach(r => {
    const tr = el('tr');
    const first = el('td');
    first.appendChild(el('span', 'dot ' + r.st));
    first.appendChild(el('span', 'sync-what', r.what));
    tr.appendChild(first);
    tr.appendChild(el('td', null, r.from));
    tr.appendChild(el('td', null, r.when));
    tr.appendChild(el('td', 'dim', r.off));
    tb.appendChild(tr);
  });
  t.appendChild(tb); tw.appendChild(t); s4.appendChild(tw);
  view.appendChild(s4);

  view.appendChild(el('p', 'hint', 'Full detail: docs/design/the-catalog.md'));
}

/* ---------- input ---------- */
$('#ftoggle').addEventListener('click', () => {
  const open = $('#rail').classList.toggle('open');
  $('#ftoggle').setAttribute('aria-expanded', String(open));
});
$('#q').addEventListener('input', e => { state.q = e.target.value; state.cursor = 0; state.qi = 0; render(); });
$('#theme').addEventListener('click', () => {
  const next = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
  document.documentElement.dataset.theme = next;
  try { localStorage.setItem('theme', next); } catch (_) { /* private mode */ }
});
(function initTheme() {
  const forced = new URLSearchParams(location.search).get('theme');
  if (forced === 'light' || forced === 'dark') { document.documentElement.dataset.theme = forced; return; }
  let saved = null;
  try { saved = localStorage.getItem('theme'); } catch (_) { /* private mode */ }
  if (saved) { document.documentElement.dataset.theme = saved; return; }
  if (window.matchMedia && matchMedia('(prefers-color-scheme: light)').matches)
    document.documentElement.dataset.theme = 'light';
})();

document.addEventListener('keydown', e => {
  const typing = e.target.matches('input, select, textarea');
  if (e.key === '/' && !typing) { e.preventDefault(); $('#q').focus(); $('#q').select(); return; }
  if (typing) { if (e.key === 'Escape') e.target.blur(); return; }
  if (e.metaKey || e.ctrlKey || e.altKey) return;

  if (state.slug) {
    if (e.key === 'Escape') go('#/browse');
    return;
  }
  if (state.mode === 'review') {
    const todo = queue().filter(x => !x.verdict);
    if (!todo.length) return;
    if (e.key === 'j' || e.key === 'k') {
      state.qi = Math.max(0, Math.min(todo.length - 1, state.qi + (e.key === 'j' ? 1 : -1)));
      renderReview(); e.preventDefault();
    } else if ('123'.includes(e.key)) {
      judge(todo[state.qi], { 1: 'right', 2: 'wrong', 3: 'unsure' }[e.key]);
    }
    return;
  }
  if (state.mode === 'browse') {
    const shows = visible();
    if (e.key === 'j' || e.key === 'k') {
      state.cursor = Math.max(0, Math.min(shows.length - 1, state.cursor + (e.key === 'j' ? 1 : -1)));
      renderBrowse();
      $('[data-cursor]')?.scrollIntoView({ block: 'nearest' });
      e.preventDefault();
    } else if (e.key === 'Enter' && shows[state.cursor]) {
      go('#/show/' + encodeURIComponent(shows[state.cursor].slug));
    }
  }
});

boot().catch(err => {
  $('#view').replaceChildren(
    el('p', 'empty', String(err.message || err)),
    el('p', 'empty', 'Run: python3 curation/arc-bakeoff/build-catalog-index.py'));
});

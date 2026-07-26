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
  f: { rule: null, feed: null, review: null, cat: '' },
  q: '', cursor: 0, qi: 0, arc: null, theme: null,
};

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
  const total = s.arcs.length + s.themes_vocab.length;
  if (!total) return 'none';
  const judged = Object.keys(r.arcs || {}).length + Object.keys(r.themes || {}).length;
  if (!judged) return 'todo';
  return judged >= total ? 'done' : 'mixed';
}

function totals() {
  let items = 0, judged = 0;
  for (const s of state.data.shows) {
    items += s.arcs.length + s.themes_vocab.length;
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
  if (s.themes_vocab.some(t => t.n.toLowerCase().includes(q))) return true;
  return s.eps.some(e => e[0].toLowerCase().includes(q));   // episode titles matter — "OceanGate"
}

function visible() {
  const q = state.q.trim().toLowerCase();
  const { rule, feed, review, cat } = state.f;
  return state.data.shows.filter(s => {
    if (cat && s.category !== cat) return false;
    if (feed && (s.small ? s.small.key : 'normal') !== feed) return false;
    if (review && showState(s) !== review) return false;
    if (rule) {
      if (rule === 'themed') { if (!s.themes_vocab.length) return false; }
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
    s.themes_vocab.forEach((t, i) => out.push({
      kind: 'theme', s, i, key: `${s.slug}#t${t.s}`, name: t.n, def: t.d, slugId: t.s,
      count: t.c, verdict: themeVerdict(s.slug, t.s),
      eps: s.eps.filter(e => e[5] === i),
    }));
  }
  return out;
}

/* ---------- routing ---------- */
function go(hash) { location.hash = hash; }
function fromHash() {
  const h = location.hash;
  const m = /^#\/show\/(.+)$/.exec(h);
  if (m) { state.slug = decodeURIComponent(m[1]); state.arc = state.theme = null; }
  else {
    state.slug = null;
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
  const mode = state.slug ? 'browse' : state.mode;
  document.body.dataset.mode = mode;
  renderModes(mode);
  renderFacets(mode);
  renderProgress();

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

  box.appendChild(facetGroup('Review state', [
    ['todo', 'Not started', count(s => showState(s) === 'todo')],
    ['mixed', 'Part-judged', count(s => showState(s) === 'mixed')],
    ['done', 'Settled', count(s => showState(s) === 'done')],
  ], state.f.review, v => set('review', v)));

  const pats = Object.entries(state.data.patterns);
  box.appendChild(facetGroup('Detected by', [
    ...(shows.some(s => s.themes_vocab.length)
      ? [['themed', 'Model themes', count(s => s.themes_vocab.length)]] : []),
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

  if (state.f.rule || state.f.feed || state.f.review || state.f.cat) {
    const clear = el('button', 'facet-clear', 'Clear filters');
    clear.onclick = () => { state.f = { rule: null, feed: null, review: null, cat: '' };
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
  const c = el('button', 'card p-' + (st === 'none' && s.themes_vocab.length ? 'model' : st));
  c.onclick = () => go('#/show/' + encodeURIComponent(s.slug));
  if (i === state.cursor) c.dataset.cursor = '1';

  const a = el('div', 'card-art');
  if (s.art) a.style.backgroundImage = `url("${art(s.art)}")`;
  else a.appendChild(el('span', null, initials(s.title)));
  c.appendChild(a);
  c.appendChild(el('div', 'card-title', s.title));
  c.appendChild(el('div', 'card-sub', s.network || s.author || ''));

  const foot = el('div', 'card-foot');
  if (s.themes_vocab.length) foot.appendChild(el('span', 'tag model', `${s.themes_vocab.length} themes`));
  if (s.arcs.length) foot.appendChild(el('span', 'tag on', `${s.arcs.length} arc${s.arcs.length > 1 ? 's' : ''}`));
  if (s.small) foot.appendChild(el('span', 'tag warn', s.small.label));
  else if (!s.arcs.length && !s.themes_vocab.length) {
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

  if (s.themes_vocab.length) {
    const sec = el('div', 'sec');
    sec.appendChild(el('h2', null, 'Themes'));
    sec.appendChild(el('span', 'count', String(s.themes_vocab.length)));
    const ag = s.themes_meta && s.themes_meta.agreement;
    if (ag && ag.primaryAgreement != null) {
      sec.appendChild(el('div', 'spacer'));
      const x = el('span', 'agree', `${Math.round(ag.primaryAgreement * 100)}% agreement across two passes`);
      x.title = 'Two independent labelling runs; where they disagree the theme boundary is fuzzy.';
      sec.appendChild(x);
    }
    view.appendChild(sec);
    const tw = el('div', 'arcs');
    s.themes_vocab.forEach((t, i) => tw.appendChild(themeCard(s, t, i, r)));
    view.appendChild(tw);
  }

  if (!s.arcs.length && !s.themes_vocab.length) {
    const g = s.small ? null : state.data.noArcGroups[s.group];
    const sec = el('div', 'sec');
    sec.appendChild(el('h2', null, 'No arcs detected'));
    if (g) sec.appendChild(el('span', 'count', g.label));
    else if (s.small) sec.appendChild(el('span', 'count', 'not enough feed to tell'));
    view.appendChild(sec);
    if (g) view.appendChild(el('p', 'ddesc', g.hint));
  }

  const sv = el('div', 'showverdict');
  sv.appendChild(el('p', null, (s.arcs.length || s.themes_vocab.length)
    ? 'Or judge the whole show at once:'
    : 'Is that right — does this show genuinely have no multi-part stories?'));
  const noneBtn = el('button', r.show ? 'on' : '', r.show ? '✓ Confirmed: no arcs here' : 'No arcs here');
  noneBtn.onclick = async () => { await saveVerdict({ slug: s.slug, kind: 'show', verdict: r.show ? 'clear' : 'none' }); render(); };
  sv.appendChild(noneBtn);
  view.appendChild(sv);

  const esec = el('div', 'sec');
  esec.appendChild(el('h2', null, 'Episodes'));
  const shown = state.arc != null ? s.eps.filter(e => e[4] === state.arc)
              : state.theme != null ? s.eps.filter(e => e[5] === state.theme) : s.eps;
  esec.appendChild(el('span', 'count', String(shown.length)));
  esec.appendChild(el('div', 'spacer'));
  if (state.arc != null || state.theme != null) {
    const label = state.arc != null ? s.arcs[state.arc].n : s.themes_vocab[state.theme].n;
    const f = el('button', 'ep-filter', `Showing: ${label}  ✕`);
    f.onclick = () => { state.arc = state.theme = null; renderDetail(); };
    esec.appendChild(f);
  }
  view.appendChild(esec);

  const list = el('div', 'eps');
  shown.forEach(e => {
    const row = el('div', 'ep' + (e[4] === -1 && e[5] === -1 ? ' off' : ''));
    row.appendChild(el('span', 'ep-date', fmtDate(e[1])));
    const body = el('span', 'ep-t');
    if (e[4] !== -1 && state.arc == null) body.appendChild(el('span', 'ep-arc', s.arcs[e[4]].n));
    else if (e[5] != null && e[5] !== -1 && state.theme == null)
      body.appendChild(el('span', 'ep-arc ep-theme', s.themes_vocab[e[5]].n));
    body.append(e[0]);
    row.appendChild(body);
    const tag = el('span');
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
  top.appendChild(el('span', 'tag model', `${t.c} episodes`));
  if (t.m) { const m = el('span', 'arc-season', 'catalog'); m.title = 'Maps to show-level theme: ' + t.m; top.appendChild(m); }
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

/* Every branch in PodcastDetailViewModel.load(), verbatim from the code. */
const CHART_LOAD = {
  w: 1180, h: 660, alt: 'Which data reaches the screen when a show is opened',
  nodes: [
    { id: 'start', cx: 472, y: 14, w: 230, h: 42, kind: 'start', label: 'You open a show' },
    { id: 'loading', cx: 472, y: 82, w: 210, h: 36, kind: 'proc', lines: ['`state = .loading`'] },
    { id: 'd1', cx: 472, y: 142, w: 268, h: 76, kind: 'dec', lines: ['Can the local', 'store be read?'] },
    { id: 'errA', cx: 900, y: 158, w: 214, h: 46, kind: 'err', lines: ['.error — nothing shown'] },
    { id: 'd2', cx: 472, y: 250, w: 300, h: 86, kind: 'dec', lines: ['Saved copy that', 'already has episodes?'] },
    { id: 'storeR', cx: 197, y: 368, w: 290, h: 54, kind: 'ok', lines: ['.loaded(saved) — on screen', 'with no network at all'] },
    { id: 'd3', cx: 197, y: 452, w: 250, h: 74, kind: 'dec', lines: ['Background', 'refresh OK?'] },
    { id: 'keep', cx: 95, y: 562, w: 190, h: 58, kind: 'muted', lines: ['Nothing happens —', 'saved view stands'] },
    { id: 'swap', cx: 300, y: 562, w: 190, h: 58, kind: 'ok', lines: ['.loaded(fresh)', 'swaps in'] },
    { id: 'd4', cx: 748, y: 368, w: 244, h: 80, kind: 'dec', lines: ['Feed fetch OK?', '(you are waiting)'] },
    { id: 'freshC', cx: 520, y: 562, w: 190, h: 58, kind: 'ok', lines: ['.loaded(fresh)'] },
    { id: 'd5', cx: 975, y: 452, w: 234, h: 74, kind: 'dec', lines: ['Any saved row', 'at all?'] },
    { id: 'emptyR', cx: 870, y: 562, w: 204, h: 66, kind: 'warn', lines: ['.loaded — but 0', 'episodes, so no shelf'] },
    { id: 'errB', cx: 1090, y: 562, w: 168, h: 46, kind: 'err', lines: ['.error'] },
  ],
  edges: [
    { from: 'start', to: 'loading' },
    { from: 'loading', to: 'd1' },
    { from: 'd1', to: 'errA', side: true, label: 'no', dim: true },
    { from: 'd1', to: 'd2', label: 'yes' },
    { from: 'd2', to: 'storeR', label: 'yes' },
    { from: 'd2', to: 'd4', label: 'no' },
    { from: 'storeR', to: 'd3' },
    { from: 'd3', to: 'keep', label: 'no', dim: true },
    { from: 'd3', to: 'swap', label: 'yes' },
    { from: 'd4', to: 'freshC', label: 'yes' },
    { from: 'd4', to: 'd5', label: 'no' },
    { from: 'd5', to: 'emptyR', label: 'yes', dim: true },
    { from: 'd5', to: 'errB', label: 'no', dim: true },
  ],
};

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

const OPEN_STEPS = [
  { t: 'You tap a show', where: 'device', when: '0 ms',
    d: 'The detail screen appears and asks for the feed. Nothing is on screen yet.',
    code: 'PodcastDetailViewModel.load()' },
  { t: 'The store answers first', where: 'device', when: 'instant',
    d: 'SwiftData is checked for a saved copy. If it already has episodes the screen renders from it immediately — the network is never on the critical path for a show you have opened before.',
    code: 'modelContext.fetch(FetchDescriptor<Podcast>)' },
  { t: 'The feed refreshes behind you', where: 'network', when: 'background',
    d: 'The RSS is fetched and upserted so new episodes and season numbers land. If it fails — offline, feed down — the failure is swallowed and what you are already reading stands. An error is never shown over live data.',
    code: 'fetcher.fetch → FeedUpsert.upsert' },
  { t: 'Arcs are derived, not stored', where: 'device', when: 'every render',
    d: 'Arcs are a computed property. Each access re-runs the grouping over the episode list from scratch — nothing is cached, so the shelf can never be stale relative to the episodes.',
    code: 'ArcDerivation.groupIntoArcs(episodes)' },
  { t: 'Grouping runs in three passes', where: 'device', when: '',
    d: 'Prefix-clustering with re-release dedup and the anthology guard; then chaptered-season cards for whatever is left over; then merge, newest arc first.',
    code: 'clusterGuarded → chapteredSeasonCards → mergeByRecency' },
  { t: 'The shelf appears — or does not', where: 'device', when: '',
    d: 'If no arcs come back, the Story arcs shelf is hidden entirely rather than showing an empty row. A singles-only show looks like it always did.',
    code: 'if !viewModel.arcs.isEmpty' },
  { t: 'You tap an arc card', where: 'device', when: '',
    d: 'The episode list filters to that arc and a “Showing: … ✕” chip appears. Add all queues the whole arc oldest-first, so it plays Part 1 → N even though the list is newest-first.',
    code: 'selectedArcID · queueStore.add' },
];

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
  ['open', 'Opening a show'],
  ['decide', 'What decides what you see'],
  ['build', 'Where the data comes from'],
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
    'Two timelines that are easy to confuse: what the phone does in the moment you open a show, '
    + 'and what this machine does — occasionally, by hand — to produce the data it reads.'));

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

  /* 1 — runtime */
  const s1 = sysHead('open', 'Opening a show',
    'Two things happen, and they are not the same thing. First the view model decides which '
    + 'episodes reach the screen — that runs once per open and branches five ways. Then the view '
    + 'decides whether an arcs shelf appears — that runs on every render.');

  s1.appendChild(el('h3', 'sub-h', 'A · Which episodes reach the screen — PodcastDetailViewModel.load()'));
  s1.appendChild(flowchart(CHART_LOAD));
  s1.appendChild(el('p', 'flow-note',
    'The left branch is the common one: open a show you have opened before and it paints from the '
    + 'local store with no network on the critical path, then quietly refreshes. A failed refresh '
    + 'there is swallowed — you are never shown an error over something you are already reading. '
    + 'You only ever wait on the network down the right branch, when there is nothing saved to show.'));

  s1.appendChild(el('h3', 'sub-h', 'B · Whether the arcs shelf appears — on every render'));
  s1.appendChild(flowchart(CHART_SHELF));
  s1.appendChild(el('p', 'flow-note',
    'Arcs are a computed property, so this whole path re-runs each time the view draws. Nothing is '
    + 'cached and nothing is looked up: no server call, no arc table, no cache to invalidate. The '
    + 'phone groups the episodes itself, from title text it already has.'));
  view.appendChild(s1);

  /* 2 — precedence */
  const s2 = sysHead('decide', 'What decides what you see',
    'When the store ships, the phone will ask these in order and stop at the first answer. Today only the third rung exists.');
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
  view.appendChild(s2);

  /* 3 — build time */
  const s3 = sysHead('build', 'Where the data comes from',
    `On this machine, not the phone. Three things propose structure and one of them is you — `
    + `${items.toLocaleString()} groupings exist, ${judged === 1 ? '1 has' : judged + ' have'} a verdict.`);
  const flow = el('div', 'flow');
  PIPELINE.forEach((col, i) => {
    if (i) flow.appendChild(el('div', 'arrow', '→'));
    const c = el('div', 'col');
    c.appendChild(el('h3', 'col-h', col.head));
    col.nodes.forEach(n => c.appendChild(node(n)));
    flow.appendChild(c);
  });
  s3.appendChild(flow);

  s3.appendChild(el('h3', 'sub-h', 'Priority when they disagree'));
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
  s3.appendChild(stack);
  s3.appendChild(el('p', 'flow-note',
    'Re-running a detector or the model can only add candidates. Neither can change a call you '
    + 'already made, because ids are matched by episode overlap rather than position.'));
  view.appendChild(s3);

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

  view.appendChild(el('p', 'hint', 'Full detail: docs/design/taxonomy-architecture.md'));
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

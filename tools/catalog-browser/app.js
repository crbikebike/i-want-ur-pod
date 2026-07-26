/* Catalog browser. Grid -> show -> arc -> episodes, with verdict capture.
   No framework, no build step. Data comes from /api/catalog (built by
   curation/arc-bakeoff/build-catalog-index.py). */

const $ = (s, r = document) => r.querySelector(s);
const el = (t, c, x) => { const n = document.createElement(t); if (c) n.className = c; if (x != null) n.textContent = x; return n; };

const state = { data: null, verdicts: {}, pattern: null, q: '', cat: '', slug: null, arc: null, theme: null, cursor: 0 };

/* Catalog artwork is stored at 3000x3000. Ask Apple for a thumbnail instead —
   315 full-size covers would be ~100MB of images for a grid of 180px tiles. */
const art = u => (u || '').replace(/\/\d+x\d+bb\./, '/300x300bb.');
const initials = t => t.replace(/^(the|a|an)\s+/i, '').split(/\s+/).slice(0, 2).map(w => w[0] || '').join('').toUpperCase();
const fmtDate = iso => {
  if (!iso) return '';
  const [y, m, d] = iso.split('-');
  return `${['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][+m]} ${+d} ${y}`;
};

/* ---------- data ---------- */
async function boot() {
  const [cat, ver] = await Promise.all([
    fetch('/api/catalog').then(r => r.ok ? r.json() : Promise.reject(new Error('catalog-index.json not built'))),
    fetch('/api/verdicts').then(r => r.json()).catch(() => ({}))
  ]);
  state.data = cat;
  state.verdicts = ver;
  renderSidebar();
  renderCategories();
  fromHash();
  render();
}

async function saveVerdict(body) {
  const res = await fetch('/api/verdicts', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body)
  });
  if (!res.ok) { console.error('verdict rejected', await res.text()); return; }
  const out = await res.json();
  if (out.verdicts) state.verdicts[body.slug] = out.verdicts;
  else delete state.verdicts[body.slug];
}

/* ---------- sidebar ---------- */
function renderSidebar() {
  const { patterns, noArcGroups, totals } = state.data;
  $('#totals').replaceChildren(
    stat(totals.shows, 'shows'), stat(totals.withArcs, 'grouped'), stat(totals.arcs, 'arcs')
  );

  const active = state.pattern
    ? (patterns[state.pattern] || noArcGroups[state.pattern.replace('group:', '')] || {}).label
    : null;
  $('#filters').firstChild
    ? $('#filters').replaceChildren(document.createTextNode(active ? 'Filter: ' + active : 'Filters'))
    : null;

  const nav = $('#patterns');
  nav.replaceChildren();
  const groups = [
    ['All shows', [[null, { label: 'Everything', arcs: totals.arcs, shows: totals.shows }]]],
    ['Title patterns', Object.entries(patterns).filter(([, v]) => v.family === 'title')],
    ['Structural rules', Object.entries(patterns).filter(([, v]) => v.family === 'structural')],
    ['Nothing works', Object.entries(noArcGroups).map(([k, v]) => ['group:' + k, v])]
  ];
  for (const [heading, items] of groups) {
    if (!items.length) continue;
    const g = el('div', 'pgroup');
    g.appendChild(el('h2', null, heading));
    items.sort((a, b) => (b[1].arcs ?? b[1].shows) - (a[1].arcs ?? a[1].shows));
    for (const [key, meta] of items) {
      const b = el('button', 'pat');
      b.appendChild(el('span', null, meta.label));
      b.appendChild(el('i', null, String(meta.shows)));
      b.title = meta.hint || '';
      b.setAttribute('aria-pressed', String(state.pattern === key));
      b.onclick = () => {
        state.pattern = key; state.slug = null; state.cursor = 0;
        location.hash = '';
        $('.sidebar').classList.remove('open');           // picking a filter closes the phone drawer
        $('#filters').setAttribute('aria-expanded', 'false');
        renderSidebar(); render();
      };
      g.appendChild(b);
    }
    nav.appendChild(g);
  }
}
const stat = (n, label) => { const s = el('span'); s.appendChild(el('b', null, String(n))); s.append(' ' + label); return s; };

function renderCategories() {
  const cats = [...new Set(state.data.shows.map(s => s.category).filter(Boolean))].sort();
  const sel = $('#cat');
  sel.replaceChildren(new Option('All categories', ''));
  cats.forEach(c => sel.appendChild(new Option(c, c)));
  sel.value = state.cat;
}

/* ---------- filtering ---------- */
function visible() {
  const q = state.q.trim().toLowerCase();
  return state.data.shows.filter(s => {
    if (state.cat && s.category !== state.cat) return false;
    if (state.pattern) {
      if (state.pattern.startsWith('group:')) {
        if (s.group !== state.pattern.slice(6)) return false;
      } else if (!s.patterns.includes(state.pattern)) return false;
    }
    if (q && !(s.title.toLowerCase().includes(q) || (s.author || '').toLowerCase().includes(q))) return false;
    return true;
  });
}

/* ---------- routing ---------- */
/* One hash route, so a show is linkable and the back button behaves. */
function openShow(slug) {
  state.slug = slug; state.arc = null; state.theme = null; state.cursor = 0;
  location.hash = slug ? '#/show/' + encodeURIComponent(slug) : '';
  // Render here rather than leaning on hashchange: it fires asynchronously, and by then
  // fromHash() sees state already matching and bails, so nothing would ever draw.
  render();
  window.scrollTo(0, 0);
}

function fromHash() {
  const m = /^#\/show\/(.+)$/.exec(location.hash);
  const slug = m ? decodeURIComponent(m[1]) : null;
  if (slug === state.slug) return;
  state.slug = slug; state.arc = null; state.theme = null; state.cursor = 0;
  if (state.data) render();
}
window.addEventListener('hashchange', fromHash);

/* ---------- render ---------- */
function render() {
  state.slug ? renderDetail() : renderGrid();
}

function renderGrid() {
  const shows = visible();
  $('#count').textContent = `${shows.length} shows`;
  const view = $('#view');
  view.replaceChildren();

  if (!shows.length) { view.appendChild(el('p', 'empty', 'Nothing matches those filters.')); return; }
  if (state.cursor >= shows.length) state.cursor = 0;

  const grid = el('div', 'grid');
  shows.forEach((s, i) => grid.appendChild(showCard(s, i)));
  view.appendChild(grid);
  view.appendChild(el('p', 'hint', 'j / k to move · enter to open'));
}

function showCard(s, i) {
  const c = el('button', 'card');
  c.onclick = () => openShow(s.slug);
  if (i === state.cursor) c.dataset.cursor = '1';

  const a = el('div', 'card-art');
  if (s.art) a.style.backgroundImage = `url("${art(s.art)}")`;
  else a.appendChild(el('span', null, initials(s.title)));
  c.appendChild(a);

  c.appendChild(el('div', 'card-title', s.title));
  c.appendChild(el('div', 'card-sub', s.network || s.author || ''));

  const foot = el('div', 'card-foot');
  if ((s.themes_vocab || []).length) {
    foot.appendChild(el('span', 'tag struct', `${s.themes_vocab.length} themes`));
  }
  if (s.arcs.length) {
    foot.appendChild(el('span', 'tag on', `${s.arcs.length} arc${s.arcs.length > 1 ? 's' : ''}`));
    s.patterns.slice(0, 2).forEach(p => {
      const meta = state.data.patterns[p];
      if (meta) foot.appendChild(el('span', 'tag' + (meta.family === 'structural' ? ' struct' : ''), meta.label));
    });
  } else if (s.small) {
    // why the feed is nearly empty beats "no arcs found", which blames the detector
    foot.appendChild(el('span', 'tag warn', s.small.label));
  } else {
    const g = state.data.noArcGroups[s.group];
    foot.appendChild(el('span', 'tag none', g ? g.label : 'no arcs'));
  }
  if (s.small && s.arcs.length) foot.appendChild(el('span', 'tag warn', s.small.label));
  c.appendChild(foot);

  const v = verdictMark(s.slug);
  if (v) c.appendChild(el('div', 'judged ' + v));
  return c;
}

function verdictMark(slug) {
  const rec = state.verdicts[slug];
  if (!rec) return null;
  if (rec.show) return 'none';
  const vs = [...Object.values(rec.arcs || {}), ...Object.values(rec.themes || {})].map(a => a.v);
  if (!vs.length) return null;
  if (vs.includes('wrong')) return 'wrong';
  if (vs.includes('unsure')) return 'unsure';
  return 'right';
}

/* ---------- detail ---------- */
function renderDetail() {
  const s = state.data.shows.find(x => x.slug === state.slug);
  if (!s) { return openShow(null); }
  const rec = state.verdicts[s.slug] || { show: null, arcs: {} };
  const view = $('#view');
  view.replaceChildren();
  $('#count').textContent = '';

  const back = el('button', 'back', '← Catalog');
  back.onclick = () => openShow(null);
  view.appendChild(back);

  // header
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

  const stats = el('div', 'dstats');
  const plural = (n, one, many) => (n === 1 ? one : many);
  [[s.nEps, plural(s.nEps, 'episode', 'episodes')],
   [s.span, plural(s.span, 'month of publishing', 'months of publishing')],
   [s.seasons, plural(s.seasons, 'season tag', 'season tags')],
   [s.arcs.length, plural(s.arcs.length, 'arc', 'arcs')]]
    .forEach(([n, l]) => stats.appendChild(stat(n, l)));
  meta.appendChild(stats);

  const chips = el('div', 'dchips');
  s.patterns.forEach(p => {
    const m = state.data.patterns[p];
    if (m) { const t = el('span', 'tag' + (m.family === 'structural' ? ' struct' : ''), m.label); t.title = m.hint; chips.appendChild(t); }
  });
  (s.themes || []).forEach(t => {
    const th = state.data.themes[t];
    if (th) chips.appendChild(el('span', 'tag', th.name));
  });
  if (chips.childElementCount) meta.appendChild(chips);
  head.appendChild(meta);
  view.appendChild(head);

  // Say why a feed is nearly empty. Almost always the publisher's choice, not ours.
  if (s.small) {
    const box = el('div', 'feednote');
    box.appendChild(el('strong', null, s.small.label));
    box.appendChild(el('span', null, ' — ' + s.small.why + '.'));
    if (s.access && s.access !== 'free-public') {
      box.appendChild(el('span', 'tag warn', s.access.replace(/-/g, ' ')));
    }
    box.appendChild(el('p', null,
      'The fetch takes up to 800 episodes, so this is what the feed served — not a truncated download. '
      + 'A subscriber’s own feed URL would carry the full archive.'));
    view.appendChild(box);
  }

  // arcs
  if (s.arcs.length) {
    const sec = el('div', 'sec');
    sec.appendChild(el('h2', null, 'Story arcs'));
    sec.appendChild(el('span', 'count', String(s.arcs.length)));
    view.appendChild(sec);

    const wrap = el('div', 'arcs');
    s.arcs.forEach((arc, i) => wrap.appendChild(arcCard(s, arc, i, rec)));
    view.appendChild(wrap);
  } else {
    // A feed note already explains the show; the generic bucket hint would only
    // contradict it (TAL is "unnumbered" by the bucket and 884-892 by the note).
    const g = s.small ? null : state.data.noArcGroups[s.group];
    const sec = el('div', 'sec');
    sec.appendChild(el('h2', null, 'No arcs detected'));
    if (g) sec.appendChild(el('span', 'count', g.label));
    else if (s.small) sec.appendChild(el('span', 'count', 'not enough feed to tell'));
    view.appendChild(sec);
    if (g) view.appendChild(el('p', 'ddesc', g.hint));
  }

  // themes — anthologies have no arcs, but their episodes still cluster by subject
  if ((s.themes_vocab || []).length) {
    const tsec = el('div', 'sec');
    tsec.appendChild(el('h2', null, 'Themes'));
    tsec.appendChild(el('span', 'count', String(s.themes_vocab.length)));
    const ag = s.themes_meta && s.themes_meta.agreement;
    if (ag && ag.primaryAgreement != null) {
      tsec.appendChild(el('div', 'spacer'));
      const a = el('span', 'agree', `${Math.round(ag.primaryAgreement * 100)}% agreement across two passes`);
      a.title = 'Two independent labelling runs; where they disagree the theme boundary is fuzzy.';
      tsec.appendChild(a);
    }
    view.appendChild(tsec);

    const tw = el('div', 'arcs');
    s.themes_vocab.forEach((t, i) => tw.appendChild(themeCard(s, t, i, rec)));
    view.appendChild(tw);
  }

  // show-level verdict
  const sv = el('div', 'showverdict');
  sv.appendChild(el('p', null, s.arcs.length
    ? 'Or judge the whole show at once:'
    : 'Is that right — does this show genuinely have no multi-part stories?'));
  const noneBtn = el('button', rec.show ? 'on' : '', rec.show ? '✓ Confirmed: no arcs here' : 'No arcs here');
  noneBtn.onclick = async () => {
    await saveVerdict({ slug: s.slug, kind: 'show', verdict: rec.show ? 'clear' : 'none' });
    renderDetail();
  };
  sv.appendChild(noneBtn);
  view.appendChild(sv);

  // episodes
  const esec = el('div', 'sec');
  esec.appendChild(el('h2', null, 'Episodes'));
  const shown = state.arc != null ? s.eps.filter(e => e[4] === state.arc)
              : state.theme != null ? s.eps.filter(e => e[5] === state.theme)
              : s.eps;
  esec.appendChild(el('span', 'count', String(shown.length)));
  esec.appendChild(el('div', 'spacer'));
  if (state.arc != null || state.theme != null) {
    const label = state.arc != null ? s.arcs[state.arc].n : s.themes_vocab[state.theme].n;
    const f = el('button', 'ep-filter', `Showing: ${label}  ✕`);
    f.onclick = () => { state.arc = null; state.theme = null; renderDetail(); };
    esec.appendChild(f);
  }
  view.appendChild(esec);

  const list = el('div', 'eps');
  shown.forEach(e => {
    const row = el('div', 'ep' + (e[4] === -1 ? ' off' : ''));
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
  if (state.arc == null && s.eps.length < s.nEps)
    view.appendChild(el('p', 'trim', `Showing ${s.eps.length} of ${s.nEps} episodes — every arc member, plus a sample of the rest.`));
  view.appendChild(el('p', 'hint', 'j / k arcs · 1 right · 2 wrong · 3 unsure · 0 clear · n no arcs · esc back'));
}

function themeCard(s, t, i, rec) {
  const card = el('div', 'arc theme' + (state.theme === i ? ' active' : ''));
  const top = el('div', 'arc-top');
  top.appendChild(el('span', 'tag struct', `${t.c} episodes`));
  if (t.m) {
    const m = el('span', 'arc-season', 'catalog');
    m.title = 'Maps to the show-level theme: ' + t.m;
    top.appendChild(m);
  }
  card.appendChild(top);

  const name = el('div', 'arc-name', t.n);
  name.onclick = () => { state.theme = state.theme === i ? null : i; state.arc = null; renderDetail(); };
  card.appendChild(name);

  const def = el('div', 'theme-def', t.d);
  def.onclick = name.onclick;
  card.appendChild(def);

  const vs = el('div', 'verdicts');
  const cur = (rec.themes || {})[t.s];
  [['right', '✓'], ['wrong', '✗'], ['unsure', '?']].forEach(([v, glyph]) => {
    const b = el('button', 'v' + (cur && cur.v === v ? ' on-' + v : ''), glyph);
    b.title = v === 'right' ? 'this is a real category' : v === 'wrong' ? 'not a real category' : 'not sure';
    b.setAttribute('aria-label', `Mark theme "${t.n}" ${v}`);
    b.onclick = async e => {
      e.stopPropagation();
      await saveVerdict({ slug: s.slug, kind: 'theme', theme: t.s,
                          verdict: cur && cur.v === v ? 'clear' : v, name: t.n });
      renderDetail();
    };
    vs.appendChild(b);
  });
  card.appendChild(vs);
  return card;
}

function arcCard(s, arc, i, rec) {
  const card = el('div', 'arc' + (state.arc === i ? ' active' : '') + (state.cursor === i ? ' cursor' : ''));
  const top = el('div', 'arc-top');
  const pat = state.data.patterns[arc.p];
  top.appendChild(el('span', 'tag' + (pat && pat.family === 'structural' ? ' struct' : ''), pat ? pat.label : arc.p));
  if (arc.s != null) top.appendChild(el('span', 'arc-season', 'S' + arc.s));
  card.appendChild(top);

  const name = el('div', 'arc-name', arc.n);
  name.onclick = () => { state.arc = state.arc === i ? null : i; state.cursor = i; renderDetail(); };
  card.appendChild(name);

  const parts = el('div', 'arc-parts', `${arc.c} episodes`);
  parts.onclick = name.onclick;
  card.appendChild(parts);

  const vs = el('div', 'verdicts');
  const cur = (rec.arcs || {})[String(i)];
  [['right', '✓'], ['wrong', '✗'], ['unsure', '?']].forEach(([v, glyph]) => {
    const b = el('button', 'v' + (cur && cur.v === v ? ' on-' + v : ''), glyph);
    b.title = v;
    b.setAttribute('aria-label', `Mark "${arc.n}" ${v}`);
    b.onclick = async e => {
      e.stopPropagation();
      await saveVerdict({ slug: s.slug, kind: 'arc', index: i, verdict: cur && cur.v === v ? 'clear' : v,
                          name: arc.n, count: arc.c });
      renderDetail();
    };
    vs.appendChild(b);
  });
  card.appendChild(vs);
  return card;
}

/* ---------- input ---------- */
$('#q').addEventListener('input', e => { state.q = e.target.value; state.cursor = 0; if (!state.slug) render(); });
$('#cat').addEventListener('change', e => { state.cat = e.target.value; state.cursor = 0; if (!state.slug) render(); });

$('#filters').addEventListener('click', () => {
  const open = $('.sidebar').classList.toggle('open');
  $('#filters').setAttribute('aria-expanded', String(open));
});

$('#theme').addEventListener('click', () => {
  const next = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
  document.documentElement.dataset.theme = next;
  try { localStorage.setItem('theme', next); } catch (_) { /* private mode */ }
});
/* Theme precedence: explicit ?theme= in the URL, then a saved choice, then the OS.
   Dark stays the fallback — it's the kit's hero theme. */
(function initTheme() {
  const forced = new URLSearchParams(location.search).get('theme');
  if (forced === 'light' || forced === 'dark') { document.documentElement.dataset.theme = forced; return; }
  let saved = null;
  try { saved = localStorage.getItem('theme'); } catch (_) { /* private mode */ }
  if (saved) { document.documentElement.dataset.theme = saved; return; }
  if (window.matchMedia && matchMedia('(prefers-color-scheme: light)').matches)
    document.documentElement.dataset.theme = 'light';
})();

document.addEventListener('keydown', async e => {
  if (e.target.matches('input, select, textarea') || e.metaKey || e.ctrlKey || e.altKey) return;
  const show = state.slug && state.data ? state.data.shows.find(x => x.slug === state.slug) : null;

  if (e.key === 'Escape' && show) { openShow(null); return; }

  if (!show) {
    const shows = visible();
    if (e.key === 'j' || e.key === 'k') {
      state.cursor = Math.max(0, Math.min(shows.length - 1, state.cursor + (e.key === 'j' ? 1 : -1)));
      renderGrid();
      document.querySelector('[data-cursor]')?.scrollIntoView({ block: 'nearest' });
      e.preventDefault();
    } else if (e.key === 'Enter' && shows[state.cursor]) {
      openShow(shows[state.cursor].slug);
    }
    return;
  }

  if (e.key === 'j' || e.key === 'k') {
    if (!show.arcs.length) return;
    state.cursor = Math.max(0, Math.min(show.arcs.length - 1, state.cursor + (e.key === 'j' ? 1 : -1)));
    renderDetail();
    document.querySelector('.arc.cursor')?.scrollIntoView({ block: 'nearest' });
    e.preventDefault();
  } else if (e.key === 'n') {
    const rec = state.verdicts[show.slug] || {};
    await saveVerdict({ slug: show.slug, kind: 'show', verdict: rec.show ? 'clear' : 'none' });
    renderDetail();
  } else if ('1230'.includes(e.key) && show.arcs[state.cursor]) {
    const map = { '1': 'right', '2': 'wrong', '3': 'unsure', '0': 'clear' };
    const arc = show.arcs[state.cursor];
    await saveVerdict({ slug: show.slug, kind: 'arc', index: state.cursor, verdict: map[e.key],
                        name: arc.n, count: arc.c });
    renderDetail();
  }
});

boot().catch(err => {
  $('#view').replaceChildren(
    el('p', 'empty', String(err.message || err)),
    el('p', 'empty', 'Run: python3 curation/arc-bakeoff/build-catalog-index.py')
  );
});

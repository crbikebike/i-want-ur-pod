// Narrative Podcast Atlas — build step.
// Reads durable sources in this folder, regenerates atlas-data.json, podcast-atlas.csv, podcast-atlas.html.
//   atlas-source.json  — the catalog you edit ({shows, arcs, stats}). Add a show: append to shows[],
//                        and add its title to any arcs[].shows[] lists you want it to appear under.
//   episodes.json      — curated "episodes you can't miss"
// Run:  node curation/build-atlas.mjs   (from repo root)
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const DIR = dirname(fileURLToPath(import.meta.url));
const readJSON = (f, fallback) => { try { return JSON.parse(readFileSync(join(DIR, f), 'utf8')); } catch { return fallback; } };

const source = readJSON('atlas-source.json', { shows: [], arcs: [] });
const episodes = readJSON('episodes.json', []);

const ACCESS = {
  'free-public':          { label: 'Free',        hue: 'free' },
  'early-access-paywall': { label: 'Early-access', hue: 'early' },
  'subscription-only':    { label: 'Subscription', hue: 'sub' },
  'platform-locked':      { label: 'App-locked',   hue: 'lock' },
  'unknown':              { label: 'Unknown',      hue: 'unk' },
};
const norm = t => String(t || '').toLowerCase().replace(/^(the|a|an)\s+/, '').replace(/[^a-z0-9]+/g, '').trim();

const arcs = source.arcs;
const rawShows = source.shows;

// dedup shows by normalized title
const seen = new Map();
for (const s of rawShows) { const k = norm(s.title); if (k && !seen.has(k)) seen.set(k, s); }
const cleanShows = [...seen.values()].map((s, i) => ({
  id: i, title: s.title || '', network: s.network || '', years: s.years || '',
  description: s.description || '', seasons: s.notableSeasons || '',
  access: ACCESS[s.feedAccess] ? s.feedAccess : 'unknown',
  tags: Array.isArray(s.themeTags) ? s.themeTags : [], why: s.whyNotable || '',
}));

// resolve arcs -> show ids
const byNorm = new Map();
cleanShows.forEach(s => { const k = norm(s.title); if (k && !byNorm.has(k)) byNorm.set(k, s.id); });
const cleanArcs = arcs.map(a => {
  const ids = [...new Set((a.shows || []).map(t => byNorm.get(norm(t))).filter(v => v !== undefined))];
  return { arc: a.arc, slug: a.slug || norm(a.arc), description: a.description || '', showIds: ids };
}).filter(a => a.showIds.length > 0).sort((a, b) => b.showIds.length - a.showIds.length);

const payload = { shows: cleanShows, arcs: cleanArcs, episodes, access: ACCESS };

// ---- CSV + JSON ----
const csvEsc = v => { v = String(v == null ? '' : v); return /[",\n]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v; };
const csvHead = ['title', 'network', 'years', 'feed_access', 'theme_arcs', 'description', 'notable_seasons', 'why_notable'];
const csvRows = cleanShows.map(s => [s.title, s.network, s.years, s.access, s.tags.join('; '), s.description, s.seasons, s.why].map(csvEsc).join(','));
writeFileSync(join(DIR, 'podcast-atlas.csv'), [csvHead.join(','), ...csvRows].join('\n'));
writeFileSync(join(DIR, 'atlas-data.json'), JSON.stringify(payload));

// ---- HTML ----
const jsonText = JSON.stringify(payload).replace(/</g, '\\u003c');
const accCounts = {}; cleanShows.forEach(s => accCounts[s.access] = (accCounts[s.access] || 0) + 1);

const html = `<title>Narrative Podcast Atlas</title>
<style>
  :root{
    --bg:#0F1113; --panel:#171A1D; --panel-2:#1E2227; --line:#2B3036;
    --ink:#E9E6DF; --muted:#969CA3; --faint:#6D747B;
    --accent:#E9A94C; --accent-dim:#7a5a26;
    --free:#5FBE8C; --early:#5B9BD5; --sub:#E06C75; --lock:#B183D6; --unk:#8A9096;
    --shadow:0 1px 0 rgba(255,255,255,.02), 0 8px 24px rgba(0,0,0,.35);
    --radius:10px;
    --f-sans:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
    --f-mono:ui-monospace,"SF Mono",SFMono-Regular,Menlo,Consolas,"Liberation Mono",monospace;
  }
  @media (prefers-color-scheme: light){
    :root{
      --bg:#EDECE6; --panel:#FBFAF6; --panel-2:#F2F0EA; --line:#DCD9D1;
      --ink:#1B1E21; --muted:#5B6167; --faint:#878D93;
      --accent:#B9741E; --accent-dim:#e6c491;
      --free:#2E9668; --early:#3B78BE; --sub:#C0424D; --lock:#8858B8; --unk:#71787E;
      --shadow:0 1px 2px rgba(0,0,0,.05), 0 8px 20px rgba(0,0,0,.06);
    }
  }
  :root[data-theme="dark"]{
    --bg:#0F1113; --panel:#171A1D; --panel-2:#1E2227; --line:#2B3036;
    --ink:#E9E6DF; --muted:#969CA3; --faint:#6D747B;
    --accent:#E9A94C; --accent-dim:#7a5a26;
    --free:#5FBE8C; --early:#5B9BD5; --sub:#E06C75; --lock:#B183D6; --unk:#8A9096;
    --shadow:0 1px 0 rgba(255,255,255,.02), 0 8px 24px rgba(0,0,0,.35);
  }
  :root[data-theme="light"]{
    --bg:#EDECE6; --panel:#FBFAF6; --panel-2:#F2F0EA; --line:#DCD9D1;
    --ink:#1B1E21; --muted:#5B6167; --faint:#878D93;
    --accent:#B9741E; --accent-dim:#e6c491;
    --free:#2E9668; --early:#3B78BE; --sub:#C0424D; --lock:#8858B8; --unk:#71787E;
    --shadow:0 1px 2px rgba(0,0,0,.05), 0 8px 20px rgba(0,0,0,.06);
  }

  *{box-sizing:border-box}
  body{background:var(--bg);color:var(--ink);font-family:var(--f-sans);line-height:1.5;-webkit-font-smoothing:antialiased;margin:0}
  .wrap{max-width:1140px;margin:0 auto;padding:0 20px 80px}

  header.top{border-bottom:1px solid var(--line);background:linear-gradient(180deg,var(--panel),var(--bg));}
  .top-inner{max-width:1140px;margin:0 auto;padding:26px 20px 20px}
  .eyebrow{font-family:var(--f-mono);font-size:11px;letter-spacing:.22em;text-transform:uppercase;color:var(--accent);margin:0 0 10px}
  h1{font-size:clamp(28px,4.5vw,44px);line-height:1.02;letter-spacing:-.02em;margin:0;font-weight:800;text-wrap:balance}
  .sub{color:var(--muted);margin:12px 0 0;max-width:60ch}
  .statstrip{display:flex;flex-wrap:wrap;gap:22px;margin-top:20px;font-family:var(--f-mono);font-size:12px;align-items:flex-end}
  .stat b{display:block;font-size:22px;font-weight:700;color:var(--ink);font-variant-numeric:tabular-nums;letter-spacing:-.01em}
  .stat span{color:var(--faint);letter-spacing:.04em}
  .accessbar{display:flex;height:8px;border-radius:99px;overflow:hidden;min-width:220px;flex:1;max-width:420px;border:1px solid var(--line)}
  .accessbar i{display:block;height:100%}

  .rail{position:sticky;top:0;z-index:20;background:color-mix(in srgb,var(--bg) 88%, transparent);backdrop-filter:blur(8px);border-bottom:1px solid var(--line)}
  .rail-inner{max-width:1140px;margin:0 auto;padding:12px 20px;display:flex;flex-direction:column;gap:12px}
  .tabs{display:flex;gap:4px}
  .tab{font-family:var(--f-mono);font-size:12px;letter-spacing:.04em;text-transform:uppercase;color:var(--muted);background:none;border:0;padding:8px 12px;border-radius:8px;cursor:pointer}
  .tab:hover{color:var(--ink);background:var(--panel-2)}
  .tab[aria-selected="true"]{color:var(--bg);background:var(--accent)}
  @media (prefers-color-scheme:light){.tab[aria-selected="true"]{color:#fff}}
  :root[data-theme="light"] .tab[aria-selected="true"]{color:#fff}

  .controls{display:flex;flex-wrap:wrap;gap:10px;align-items:center}
  .search{flex:1;min-width:180px;display:flex;align-items:center;gap:8px;background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:8px 12px}
  .search input{flex:1;background:none;border:0;color:var(--ink);font-family:var(--f-sans);font-size:14px;outline:none}
  .search svg{flex:none;color:var(--faint)}
  select{background:var(--panel);border:1px solid var(--line);border-radius:8px;color:var(--ink);padding:8px 10px;font-family:var(--f-mono);font-size:12px;max-width:220px}
  .chips{display:flex;flex-wrap:wrap;gap:6px}
  .chip{font-family:var(--f-mono);font-size:11px;letter-spacing:.03em;padding:6px 10px;border-radius:99px;border:1px solid var(--line);background:var(--panel);color:var(--muted);cursor:pointer;display:inline-flex;align-items:center;gap:6px}
  .chip:hover{color:var(--ink);border-color:var(--faint)}
  .chip[aria-pressed="true"]{color:var(--ink);border-color:currentColor}
  .chip .dot{width:8px;height:8px;border-radius:99px;background:currentColor}
  .chip.free[aria-pressed="true"]{color:var(--free)} .chip.early[aria-pressed="true"]{color:var(--early)}
  .chip.sub[aria-pressed="true"]{color:var(--sub)} .chip.lock[aria-pressed="true"]{color:var(--lock)}
  .chip.all[aria-pressed="true"]{color:var(--accent)}
  .resultline{font-family:var(--f-mono);font-size:12px;color:var(--faint);display:flex;gap:12px;align-items:center}
  .resultline b{color:var(--ink);font-variant-numeric:tabular-nums}
  .btn-clear{font-family:var(--f-mono);font-size:11px;color:var(--muted);background:none;border:1px solid var(--line);border-radius:7px;padding:5px 9px;cursor:pointer}
  .btn-clear:hover{color:var(--ink);border-color:var(--faint)}

  .grid{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-top:20px}
  @media (max-width:720px){.grid{grid-template-columns:1fr}}
  .card{background:var(--panel);border:1px solid var(--line);border-radius:var(--radius);padding:16px 16px 14px;box-shadow:var(--shadow);display:flex;flex-direction:column;gap:8px}
  .card-h{display:flex;justify-content:space-between;gap:12px;align-items:baseline}
  .card-h h3{margin:0;font-size:16px;font-weight:700;letter-spacing:-.01em;line-height:1.2}
  .meta{font-family:var(--f-mono);font-size:11px;color:var(--faint);margin-top:3px;letter-spacing:.02em}
  .access{font-family:var(--f-mono);font-size:10px;letter-spacing:.05em;text-transform:uppercase;padding:4px 8px;border-radius:99px;white-space:nowrap;display:inline-flex;align-items:center;gap:5px;flex:none}
  .access .dot{width:7px;height:7px;border-radius:99px;background:currentColor}
  .access.free{color:var(--free);background:color-mix(in srgb,var(--free) 14%,transparent)}
  .access.early{color:var(--early);background:color-mix(in srgb,var(--early) 15%,transparent)}
  .access.sub{color:var(--sub);background:color-mix(in srgb,var(--sub) 15%,transparent)}
  .access.lock{color:var(--lock);background:color-mix(in srgb,var(--lock) 15%,transparent)}
  .access.unk{color:var(--unk);background:color-mix(in srgb,var(--unk) 15%,transparent)}
  .desc{font-size:13.5px;color:var(--ink);opacity:.92;margin:0}
  .seasons{font-size:12.5px;color:var(--muted);margin:0;border-left:2px solid var(--accent-dim);padding-left:10px}
  .seasons b{color:var(--ink);font-weight:600}
  .tags{display:flex;flex-wrap:wrap;gap:5px;margin-top:2px}
  .tag{font-family:var(--f-mono);font-size:10px;color:var(--muted);background:var(--panel-2);border:1px solid var(--line);border-radius:6px;padding:3px 7px;cursor:pointer;letter-spacing:.02em}
  .tag:hover{color:var(--accent);border-color:var(--accent-dim)}
  .why{font-size:12px;color:var(--faint);margin:0}
  .why::before{content:"★ ";color:var(--accent)}

  .arclist{margin-top:20px;display:flex;flex-direction:column;gap:2px}
  .arc{display:grid;grid-template-columns:minmax(180px,260px) 1fr auto;gap:14px;align-items:center;padding:12px 12px;border-radius:9px;cursor:pointer;border:1px solid transparent}
  .arc:hover{background:var(--panel);border-color:var(--line)}
  .arc-name{font-weight:600;font-size:14.5px}
  .arc-name small{display:block;font-family:var(--f-sans);font-weight:400;font-size:12px;color:var(--faint);margin-top:2px;line-height:1.35}
  .arc-track{height:10px;background:var(--panel-2);border-radius:99px;overflow:hidden;border:1px solid var(--line)}
  .arc-fill{height:100%;background:linear-gradient(90deg,var(--accent-dim),var(--accent));border-radius:99px}
  .arc-count{font-family:var(--f-mono);font-size:13px;color:var(--ink);font-variant-numeric:tabular-nums;min-width:34px;text-align:right}
  .arc-count span{color:var(--faint);font-size:11px}
  @media (max-width:640px){.arc{grid-template-columns:1fr auto}.arc-track{display:none}}

  .eps{margin-top:20px;display:flex;flex-direction:column;gap:12px}
  .ep{background:var(--panel);border:1px solid var(--line);border-radius:var(--radius);padding:16px;display:flex;gap:16px;align-items:flex-start;box-shadow:var(--shadow)}
  .ep-num{font-family:var(--f-mono);font-size:12px;color:var(--accent);padding-top:3px}
  .ep h3{margin:0;font-size:17px;font-weight:700;letter-spacing:-.01em}
  .ep .meta{margin-top:5px}
  .ep p{margin:8px 0 0;font-size:13.5px;color:var(--muted)}
  .note{margin-top:22px;font-family:var(--f-mono);font-size:12px;color:var(--faint);border:1px dashed var(--line);border-radius:9px;padding:12px 14px;line-height:1.6}
  .note b{color:var(--muted)}

  .sectionhead{display:flex;align-items:baseline;justify-content:space-between;gap:12px;margin-top:24px}
  .sectionhead h2{font-size:15px;font-family:var(--f-mono);text-transform:uppercase;letter-spacing:.14em;color:var(--muted);font-weight:600;margin:0}
  .empty{text-align:center;color:var(--faint);font-family:var(--f-mono);font-size:13px;padding:60px 0}
  .hidden{display:none !important}
  a{color:var(--accent)}
  :focus-visible{outline:2px solid var(--accent);outline-offset:2px;border-radius:6px}
  @media (prefers-reduced-motion:reduce){*{transition:none!important;animation:none!important}}
</style>

<header class="top">
  <div class="top-inner">
    <p class="eyebrow">i want ur pod · curation reference</p>
    <h1>Narrative Podcast Atlas</h1>
    <p class="sub">An exhaustive, feed-flagged catalog of narrative &amp; documentary podcasts — reported journalism, narrative history, and fiction-as-journalism — clustered by the story-arcs that recur across shows. No talk shows.</p>
    <div class="statstrip">
      <div class="stat"><b>${cleanShows.length}</b><span>shows</span></div>
      <div class="stat"><b>${cleanArcs.length}</b><span>cross-show arcs</span></div>
      <div class="stat"><b>${accCounts['free-public'] || 0}</b><span>free public feeds</span></div>
      <div class="stat" style="flex:1;min-width:220px">
        <span style="margin-bottom:6px;display:block">feed access</span>
        <div class="accessbar" id="accessbar" title="feed availability across the catalog"></div>
      </div>
    </div>
  </div>
</header>

<div class="rail">
  <div class="rail-inner">
    <div class="tabs" role="tablist">
      <button class="tab" role="tab" aria-selected="true" data-view="shows">Shows</button>
      <button class="tab" role="tab" aria-selected="false" data-view="arcs">Arcs</button>
      <button class="tab" role="tab" aria-selected="false" data-view="episodes">Episodes you can't miss</button>
    </div>
    <div class="controls" id="showControls">
      <label class="search">
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/></svg>
        <input id="q" type="search" placeholder="Search title, network, description…" aria-label="Search shows">
      </label>
      <select id="arcSel" aria-label="Filter by arc"><option value="">All arcs</option></select>
      <select id="netSel" aria-label="Filter by network"><option value="">All networks</option></select>
    </div>
    <div class="controls" id="accessChips">
      <div class="chips">
        <button class="chip all" data-acc="" aria-pressed="true"><span class="dot"></span>All access</button>
        <button class="chip free" data-acc="free-public" aria-pressed="false"><span class="dot"></span>Free</button>
        <button class="chip early" data-acc="early-access-paywall" aria-pressed="false"><span class="dot"></span>Early-access</button>
        <button class="chip sub" data-acc="subscription-only" aria-pressed="false"><span class="dot"></span>Subscription</button>
        <button class="chip lock" data-acc="platform-locked" aria-pressed="false"><span class="dot"></span>App-locked</button>
      </div>
      <div class="resultline">
        <span><b id="count">0</b> shown</span>
        <button class="btn-clear" id="clear">clear filters</button>
      </div>
    </div>
  </div>
</div>

<div class="wrap">
  <div id="view-shows"><div class="grid" id="showGrid"></div><div class="empty hidden" id="showEmpty">No shows match those filters.</div></div>
  <div id="view-arcs" class="hidden">
    <div class="sectionhead"><h2>Arcs that span the catalog</h2><span class="resultline">bar = shows sharing the arc</span></div>
    <div class="arclist" id="arcList"></div>
  </div>
  <div id="view-episodes" class="hidden">
    <div class="sectionhead"><h2>Episodes you can't miss</h2><span class="resultline" id="epCount"></span></div>
    <div class="eps" id="epList"></div>
    <div class="note"><b>Growing list.</b> Standout single episodes worth a cold-start recommendation, separate from whole-show entries. Edit <b>curation/episodes.json</b> and rebuild.</div>
  </div>
</div>

<script id="data" type="application/json">${jsonText}</script>
<script>
(function(){
  const D = JSON.parse(document.getElementById('data').textContent);
  const ACC = D.access;
  const shows = D.shows, arcs = D.arcs, eps = D.episodes;
  const maxArc = Math.max.apply(null, arcs.map(a=>a.showIds.length));

  const order=['free-public','early-access-paywall','subscription-only','platform-locked','unknown'];
  const cnt={}; shows.forEach(s=>cnt[s.access]=(cnt[s.access]||0)+1);
  const ab=document.getElementById('accessbar');
  order.forEach(k=>{ if(!cnt[k])return; const i=document.createElement('i'); i.style.flex=cnt[k];
    i.style.background='var(--'+ACC[k].hue+')'; i.title=ACC[k].label+': '+cnt[k]; ab.appendChild(i); });

  const arcSel=document.getElementById('arcSel');
  arcs.forEach(a=>{ const o=document.createElement('option'); o.value=a.arc; o.textContent=a.arc+' ('+a.showIds.length+')'; arcSel.appendChild(o); });
  const netSel=document.getElementById('netSel');
  const nets={}; shows.forEach(s=>{ const n=s.network.split(/[\\/(]/)[0].trim(); if(n)nets[n]=(nets[n]||0)+1; });
  Object.entries(nets).sort((a,b)=>b[1]-a[1]||a[0].localeCompare(b[0])).forEach(([n,c])=>{ const o=document.createElement('option'); o.value=n; o.textContent=n+' ('+c+')'; netSel.appendChild(o); });

  const state={q:'',acc:'',arc:'',net:''};
  const arcIdSet=()=>{ if(!state.arc)return null; const a=arcs.find(x=>x.arc===state.arc); return a?new Set(a.showIds):new Set(); };
  const esc=s=>String(s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
  const grid=document.getElementById('showGrid'), empty=document.getElementById('showEmpty'), countEl=document.getElementById('count');

  function render(){
    const ids=arcIdSet();
    const q=state.q.toLowerCase();
    const list=shows.filter(s=>{
      if(state.acc && s.access!==state.acc) return false;
      if(ids && !ids.has(s.id)) return false;
      if(state.net && !s.network.startsWith(state.net)) return false;
      if(q){ const hay=(s.title+' '+s.network+' '+s.description+' '+s.seasons+' '+s.tags.join(' ')).toLowerCase(); if(!hay.includes(q))return false; }
      return true;
    });
    countEl.textContent=list.length;
    grid.innerHTML=list.map(s=>{
      const a=ACC[s.access];
      const seasons=s.seasons?'<p class="seasons"><b>Standout:</b> '+esc(s.seasons)+'</p>':'';
      const why=s.why?'<p class="why">'+esc(s.why)+'</p>':'';
      const tags=s.tags.map(t=>'<button class="tag" data-tag="'+esc(t)+'">'+esc(t)+'</button>').join('');
      return '<article class="card">'
        +'<div class="card-h"><div><h3>'+esc(s.title)+'</h3><div class="meta">'+esc(s.network)+(s.years?' · '+esc(s.years):'')+'</div></div>'
        +'<span class="access '+a.hue+'"><span class="dot"></span>'+a.label+'</span></div>'
        +'<p class="desc">'+esc(s.description)+'</p>'+seasons
        +(tags?'<div class="tags">'+tags+'</div>':'')+why+'</article>';
    }).join('');
    empty.classList.toggle('hidden', list.length>0);
    grid.classList.toggle('hidden', list.length===0);
  }

  const arcListEl=document.getElementById('arcList');
  arcListEl.innerHTML=arcs.map(a=>{
    const pct=Math.round(a.showIds.length/maxArc*100);
    return '<div class="arc" data-arc="'+esc(a.arc)+'" role="button" tabindex="0">'
      +'<div class="arc-name">'+esc(a.arc)+'<small>'+esc(a.description)+'</small></div>'
      +'<div class="arc-track"><div class="arc-fill" style="width:'+pct+'%"></div></div>'
      +'<div class="arc-count">'+a.showIds.length+' <span>shows</span></div></div>';
  }).join('');

  document.getElementById('epList').innerHTML=eps.map((e,i)=>{
    const a=ACC[e.feedAccess]||ACC['unknown'];
    return '<div class="ep"><div class="ep-num">'+String(i+1).padStart(2,'0')+'</div><div>'
      +'<h3>'+esc(e.episode)+'</h3><div class="meta">'+esc(e.show)+' · '+esc(e.network)+' · '+esc(e.year)
      +' &nbsp;<span class="access '+a.hue+'" style="font-size:9px"><span class="dot"></span>'+a.label+'</span></div>'
      +'<p>'+esc(e.why)+'</p></div></div>';
  }).join('');
  document.getElementById('epCount').textContent=eps.length+' pick'+(eps.length===1?'':'s');

  document.getElementById('q').addEventListener('input',e=>{state.q=e.target.value;render();});
  arcSel.addEventListener('change',e=>{state.arc=e.target.value;render();});
  netSel.addEventListener('change',e=>{state.net=e.target.value;render();});
  document.getElementById('accessChips').addEventListener('click',e=>{
    const c=e.target.closest('.chip'); if(!c)return; state.acc=c.dataset.acc;
    document.querySelectorAll('#accessChips .chip').forEach(x=>x.setAttribute('aria-pressed', x===c));
    render();
  });
  grid.addEventListener('click',e=>{
    const t=e.target.closest('.tag'); if(!t)return;
    state.q=t.dataset.tag; document.getElementById('q').value=t.dataset.tag; state.arc=''; arcSel.value=''; render();
  });
  document.getElementById('clear').addEventListener('click',()=>{
    state.q='';state.acc='';state.arc='';state.net='';
    document.getElementById('q').value='';arcSel.value='';netSel.value='';
    document.querySelectorAll('#accessChips .chip').forEach(x=>x.setAttribute('aria-pressed', x.dataset.acc===''));
    render();
  });

  function goArc(name){ state.arc=name; arcSel.value=name; state.q=''; document.getElementById('q').value=''; setView('shows'); render();
    document.getElementById('showControls').scrollIntoView({behavior:'smooth',block:'start'}); }
  arcListEl.addEventListener('click',e=>{const a=e.target.closest('.arc');if(a)goArc(a.dataset.arc);});
  arcListEl.addEventListener('keydown',e=>{if((e.key==='Enter'||e.key===' ')&&e.target.closest('.arc')){e.preventDefault();goArc(e.target.closest('.arc').dataset.arc);}});

  function setView(v){
    document.querySelectorAll('.tab').forEach(t=>t.setAttribute('aria-selected', t.dataset.view===v));
    document.getElementById('view-shows').classList.toggle('hidden',v!=='shows');
    document.getElementById('view-arcs').classList.toggle('hidden',v!=='arcs');
    document.getElementById('view-episodes').classList.toggle('hidden',v!=='episodes');
    document.getElementById('showControls').classList.toggle('hidden',v!=='shows');
    document.getElementById('accessChips').classList.toggle('hidden',v!=='shows');
  }
  document.querySelector('.tabs').addEventListener('click',e=>{const t=e.target.closest('.tab');if(t)setView(t.dataset.view);});

  render();
})();
</script>`;

writeFileSync(join(DIR, 'podcast-atlas.html'), html);
console.log('shows:', cleanShows.length, '| arcs:', cleanArcs.length, '| access:', JSON.stringify(accCounts));

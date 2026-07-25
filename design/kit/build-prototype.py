#!/usr/bin/env python3
"""Stitch the self-contained kit screens into ONE clickable prototype.

Each screen keeps its own inlined styles + scripts, isolated inside an
<iframe srcdoc>, so there are zero CSS/JS conflicts and the file works on a
plain double-click (no server). A small parent controller wires the real
navigation: tab bar (by label), the Settings gear, the search takeover
(live typing -> states), Settings "Done", and an out-of-frame jump control
for the edge states.

Output: design/kit/screens/prototype.html  (kept next to the screens so the
screens' "../fonts/" paths still resolve inside the srcdoc).

Re-run this whenever a screen changes:  python3 design/kit/build-prototype.py
"""

from pathlib import Path

HERE = Path(__file__).resolve().parent
SCREENS = HERE / "screens"
OUT = SCREENS / "prototype.html"

# name -> (file, human label for the jump control)
SCREEN_FILES = [
    ("home",             "home.html",              "Home"),
    ("shows",            "shows.html",             "Shows"),
    ("up-next",          "up-next.html",           "Up Next"),
    ("search-start",     "search-start.html",      "Search"),
    ("search-typing",    "search-typing.html",     "Typing"),
    ("search-loading",   "search-loading.html",    "Loading"),
    ("search-results",   "search-results.html",    "Results"),
    ("search-noresults", "search-noresults.html",  "No results"),
    ("search-error",     "search-error.html",      "Error"),
    ("add-feed-url",     "add-feed-url.html",      "Add feed"),
    ("settings",         "settings.html",          "Settings"),
    ("listening-history","listening-history.html", "Listening history"),
    ("detail-aht",       "podcast-detail-american-history-tellers.html", "Detail · AHT"),
    ("detail-explorers", "podcast-detail-explorers-podcast.html",        "Detail · Explorers"),
    ("first-run",        "first-run.html",         "Onboarding"),
    ("explore-themes",   "explore-themes.html",    "Explore · Themes"),
    ("explore-theme-shows","explore-theme-shows.html","Explore · Shows"),
]

# Which buttons appear in the out-of-frame "jump" strip (name -> label).
JUMP = ["home", "shows", "up-next", "search-start", "search-typing",
        "search-loading", "search-results", "search-noresults", "search-error",
        "add-feed-url", "settings", "listening-history", "detail-aht", "detail-explorers", "first-run",
        "explore-themes", "explore-theme-shows"]


def esc_for_template_literal(s: str) -> str:
    """Make raw HTML safe inside a JS backtick template literal."""
    s = s.replace("\\", "\\\\")
    s = s.replace("`", "\\`")
    s = s.replace("${", "\\${")
    # Don't let an inner </script> close our outer <script>.
    s = s.replace("</script", "<\\/script").replace("</SCRIPT", "<\\/SCRIPT")
    return s


def main() -> None:
    screens_js = []
    labels = {}
    for name, fname, label in SCREEN_FILES:
        raw = (SCREENS / fname).read_text(encoding="utf-8")
        screens_js.append(f"  {js_key(name)}: `{esc_for_template_literal(raw)}`,")
        labels[name] = label

    screens_block = "\n".join(screens_js)
    jump_buttons = "\n".join(
        f'      <button class="jbtn" data-go="{n}">{labels[n]}</button>'
        for n in JUMP
    )

    html = PAGE.replace("/*__SCREENS__*/", screens_block) \
               .replace("<!--__JUMP__-->", jump_buttons)
    OUT.write_text(html, encoding="utf-8")
    print(f"wrote {OUT.relative_to(HERE.parent.parent)}  "
          f"({len(SCREEN_FILES)} screens, {OUT.stat().st_size // 1024} KB)")


def js_key(name: str) -> str:
    return "'" + name + "'"


PAGE = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>i want ur pod — clickable prototype</title>
<style>
  :root { color-scheme: dark; --ink:#EDE9F2; --dim:#9A93A6; --line:rgba(255,255,255,.12);
          --chip:rgba(255,255,255,.06); --chip-hi:rgba(255,255,255,.12); --coral:#FF6A4D; }
  * { box-sizing: border-box; }
  html, body { margin: 0; height: 100%; }
  body {
    font: 14px/1.4 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    color: var(--ink);
    background:
      radial-gradient(120% 60% at 85% -5%, #211a2b, transparent 60%),
      radial-gradient(90% 50% at 0% 8%, #17131e, transparent 55%),
      #0a070e;
    display: grid;
    grid-template-rows: auto 1fr;
    min-height: 100%;
  }

  /* top bar */
  .bar { display:flex; align-items:center; gap:14px; padding:12px 18px;
         border-bottom:1px solid var(--line); position:sticky; top:0; z-index:5;
         background:rgba(10,7,14,.7); backdrop-filter:blur(10px); }
  .brand { font-weight:800; letter-spacing:.01em; }
  .brand b { color:var(--coral); }
  .where { color:var(--dim); font-weight:600; }
  .spacer { flex:1; }
  .tbtn { border:1px solid var(--line); background:var(--chip); color:var(--ink);
          border-radius:999px; padding:7px 13px; font-weight:700; cursor:pointer;
          font-size:13px; }
  .tbtn:hover { background:var(--chip-hi); }

  /* stage + rail */
  .wrap { display:grid; grid-template-columns:1fr 232px; gap:0; min-height:0; }
  @media (max-width: 860px) { .wrap { grid-template-columns:1fr; } .rail { display:none; } }

  .stagewrap { display:grid; place-items:center; padding:22px 12px 40px; min-height:0; }
  iframe#stage { width:440px; height:912px; max-width:100%; border:0;
                 background:transparent; }

  /* jump rail */
  .rail { border-left:1px solid var(--line); padding:18px 16px; overflow:auto; }
  .rail h3 { margin:0 0 4px; font-size:11px; letter-spacing:.14em; text-transform:uppercase;
             color:var(--dim); font-weight:800; }
  .rail p { margin:0 0 14px; color:var(--dim); font-size:12px; line-height:1.5; }
  .jgrid { display:flex; flex-direction:column; gap:7px; }
  .jbtn { text-align:left; border:1px solid var(--line); background:var(--chip);
          color:var(--ink); border-radius:11px; padding:9px 12px; font-weight:700;
          cursor:pointer; font-size:13px; transition:background .15s, border-color .15s; }
  .jbtn:hover { background:var(--chip-hi); }
  .jbtn.active { border-color:var(--coral); color:var(--coral);
                 box-shadow:inset 0 0 0 1px var(--coral); }
  .railnote { margin-top:16px; padding-top:14px; border-top:1px solid var(--line);
              color:var(--dim); font-size:11.5px; line-height:1.55; }
  .railnote b { color:var(--ink); }

  /* mobile jump strip (shown when rail is hidden) */
  .strip { display:none; gap:7px; padding:10px 14px; overflow-x:auto;
           border-bottom:1px solid var(--line); }
  @media (max-width: 860px) { .strip { display:flex; } }
  .strip .jbtn { white-space:nowrap; }
</style>
</head>
<body>
  <div class="bar">
    <span class="brand">i want ur <b>pod</b></span>
    <span class="where">· <span id="whereName">Home</span></span>
    <span class="spacer"></span>
    <button class="tbtn" id="themeBtn">◐ Theme</button>
    <button class="tbtn" id="homeBtn">⟲ Reset to Home</button>
  </div>

  <div class="strip" id="strip">
<!--__JUMP__-->
  </div>

  <div class="wrap">
    <div class="stagewrap">
      <iframe id="stage" title="prototype"></iframe>
    </div>
    <aside class="rail">
      <h3>Flow</h3>
      <p>Click the phone — the tab bar, the Settings gear, and the Search
         takeover all work. Type in the search field to move through the
         states.</p>
      <h3>Jump to a screen</h3>
      <div class="jgrid" id="jgrid">
<!--__JUMP__-->
      </div>
      <div class="railnote">
        <b>Search flow:</b> tap Search → type → Enter runs loading → results.
        The empty ("No results") and error states are reachable from the list
        above. Tapping a result row is a placeholder — a show-detail page is a
        separate, future screen.
      </div>
    </aside>
  </div>

<script>
const SCREENS = {
/*__SCREENS__*/
};

const stage = document.getElementById('stage');
const whereName = document.getElementById('whereName');

// nav map from tab-bar label -> screen name
const TAB_TO_SCREEN = { 'Home':'home', 'Shows':'shows', 'Up Next':'up-next', 'Search':'search-start' };
const PRIMARY = new Set(['home','shows','up-next']);
const NAMES = {
  'home':'Home','shows':'Shows','up-next':'Up Next','search-start':'Search',
  'search-typing':'Search · typing','search-loading':'Search · loading',
  'search-noresults':'Search · no results','search-error':'Search · error',
  'add-feed-url':'Add feed by URL',
  'settings':'Settings','listening-history':'Settings · listening history',
  'detail-aht':'Detail · American History Tellers',
  'detail-explorers':'Detail · The Explorers Podcast','first-run':'Onboarding'
};

let theme = 'dark';
let prevPrimary = 'home';         // where Search / Settings return to
let prevScreen = 'home';          // one-level back target (for pushed Detail)
let current = null;
let pending = {};                 // opts passed into the next load

function markJump(name){
  document.querySelectorAll('.jbtn').forEach(b =>
    b.classList.toggle('active', b.dataset.go === name));
}

function nav(name, opts){
  if(!SCREENS[name]) return;
  if(current && current !== name) prevScreen = current;   // one-level back
  if(PRIMARY.has(name)) prevPrimary = name;
  pending = opts || {};
  current = name;
  whereName.textContent = NAMES[name] || name;
  markJump(name);
  stage.srcdoc = SCREENS[name];   // fires stage.onload -> wire()
}

stage.addEventListener('load', () => {
  const doc = stage.contentDocument;
  if(!doc) return;
  // apply the prototype-wide theme last so it wins over the screen's own default
  try { doc.documentElement.setAttribute('data-theme', theme); } catch(e){}
  wire(doc, current, pending);
  pending = {};
});

function go(e, name){ if(e) e.preventDefault(); nav(name); }

function wire(doc, name, opts){
  // --- primary tab bar: navigate by label ---
  doc.querySelectorAll('.tabbar:not(.takeover) .tab').forEach(btn => {
    const label = (btn.querySelector('span') || {}).textContent;
    const dest = TAB_TO_SCREEN[(label || '').trim()];
    if(dest) btn.addEventListener('click', e => go(e, dest));
  });

  // --- Settings gear ---
  const gear = doc.querySelector('.util-gear');
  if(gear) gear.addEventListener('click', e => go(e, 'settings'));

  // --- Settings "Done" -> back to the tab you came from; Listening History
  //     "Done" is pushed one level deeper (from Settings), so it returns to
  //     Settings specifically, not the primary tab. ---
  const done = doc.querySelector('.done-btn');
  if(done) done.addEventListener('click', e => go(e, name === 'listening-history' ? 'settings' : prevPrimary));

  // --- Podcast Detail back button -> the screen we came from ---
  const back = doc.querySelector('.back-btn');
  if(back) back.addEventListener('click', e => go(e, prevScreen));

  // --- tap a show tile/row -> Podcast Detail (real-data AHT is the demo target;
  //     both detail screens are also reachable from the jump rail) ---
  doc.querySelectorAll('.pcard, article.pod, .sug, .topresult').forEach(el => {
    el.addEventListener('click', e => {
      if(e.target.closest('button, a, label, input')) return;  // don't hijack controls
      go(e, 'detail-aht');
    });
  });

  // --- "See all" links on Home -> the matching destination ---
  doc.querySelectorAll('.see-all').forEach(a => {
    const head = a.closest('.sec-head, section, .shelf, div');
    const txt = (head ? head.textContent : '').toLowerCase();
    let dest = null;
    if(txt.includes('up next')) dest = 'up-next';
    else if(txt.includes('shows')) dest = 'shows';
    if(dest) a.addEventListener('click', e => go(e, dest));
  });

  // --- search takeover bar ---
  const home = doc.querySelector('.tb-home');
  if(home) home.addEventListener('click', e => go(e, 'home'));
  const cancel = doc.querySelector('.tb-cancel');
  if(cancel) cancel.addEventListener('click', e => go(e, prevPrimary));

  const input = doc.querySelector('.tb-field input');
  if(input){
    // live typing: first keystroke on the empty start screen -> suggestions
    input.addEventListener('input', () => {
      if(name === 'search-start' && input.value.trim().length > 0){
        nav('search-typing', { focus:true, value: input.value });
      }
    });
    // Enter -> loading, then settle into the (empty) results state
    input.addEventListener('keydown', e => {
      if(e.key === 'Enter'){
        const q = input.value;
        nav('search-loading', { after: 'search-results', value: q });
      }
    });
    // restore focus / typed value after a state hop
    if(opts.focus){
      try {
        input.focus();
        if(opts.value != null){
          input.value = opts.value;
          input.setSelectionRange(input.value.length, input.value.length);
        }
      } catch(e){}
    } else if(opts.value != null){
      input.value = opts.value;
    }
  }

  // auto-advance (loading -> noresults) so Enter feels live
  if(opts.after){
    setTimeout(() => { if(current === name) nav(opts.after, { value: opts.value }); }, 950);
  }

  // --- Add-feed-by-URL entry points -> the shared sheet ---
  //     Search "Have a podcast URL?" (.urlcta) + Settings "Add premium…" (.srow-tap,
  //     excluding the Listening History row, which is a different destination)
  doc.querySelectorAll('.urlcta, .srow-tap:not(.srow-history)').forEach(el =>
    el.addEventListener('click', e => go(e, 'add-feed-url')));
  //     Search no-results "Add a direct link" primary action (matched by label)
  doc.querySelectorAll('.state-actions .btn').forEach(el => {
    if((el.textContent || '').toLowerCase().includes('direct link'))
      el.addEventListener('click', e => go(e, 'add-feed-url'));
  });

  // --- Settings "Listening history" row -> the history screen ---
  doc.querySelectorAll('.srow-history').forEach(el =>
    el.addEventListener('click', e => go(e, 'listening-history')));

  // --- Listening History empty-state "Browse your shows" -> Shows tab ---
  if(name === 'listening-history'){
    doc.querySelectorAll('.state-actions .btn').forEach(el => {
      if((el.textContent || '').toLowerCase().includes('browse your shows'))
        el.addEventListener('click', e => go(e, 'shows'));
    });
  }

  // --- inside the Add-feed sheet: Cancel backs out; Add runs the happy path ---
  if(name === 'add-feed-url'){
    const cancel2 = doc.querySelector('.afu-cancel');
    if(cancel2) cancel2.addEventListener('click', e => go(e, prevScreen));
    const add = doc.querySelector('#addBtn');
    const sheet = doc.getElementById('sheet');
    let advancing = false;   // latch: the screen's own inline JS also flips ready->loading
    if(add && sheet) add.addEventListener('click', () => {
      if(advancing) return;
      advancing = true;
      sheet.setAttribute('data-state', 'loading');               // Checking…
      setTimeout(() => {
        if(current !== name) return;
        sheet.setAttribute('data-state', 'success');             // Added ✓
        setTimeout(() => { if(current === name) nav('detail-aht'); }, 1100);  // -> Podcast Detail
      }, 900);
    });
  }

  // --- onboarding: final CTA lands on Home ---
  if(name === 'first-run'){
    doc.querySelectorAll('button, a').forEach(el => {
      const t = (el.textContent || '').trim().toLowerCase();
      if(t === 'done' || t === 'start listening' || t === 'finish' || t === "let's go" || t === 'get started'){
        el.addEventListener('click', e => go(e, 'home'));
      }
    });
  }
}

// out-of-frame jump buttons
document.querySelectorAll('.jbtn').forEach(b =>
  b.addEventListener('click', () => nav(b.dataset.go)));

document.getElementById('homeBtn').addEventListener('click', () => nav('home'));
document.getElementById('themeBtn').addEventListener('click', () => {
  theme = (theme === 'dark') ? 'light' : 'dark';
  const doc = stage.contentDocument;
  if(doc) doc.documentElement.setAttribute('data-theme', theme);
});

nav('home');
</script>
</body>
</html>
"""


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Generate the Podcast Detail kit screen(s) from real feed data.

Reads design/kit/data/<slug>.json (produced by scripts/fetch-podcast-episodes.py)
and emits design/kit/screens/podcast-detail-<slug>.html — a self-contained kit
screen built from REAL episodes + derived story arcs, reusing up-next.html's
head/chrome/dock so tokens stay identical.

Design (see the plan): header (art, title, author, category, Subscribe, clamped
description) → a horizontal Story-arcs/Seasons shelf (each card: season badge,
arc name, N episodes, "Add all") → the episode list with compact icon controls
(download / play / add-to-Up-Next), each row showing arc·part or S·E · date ·
duration. Season badges only render when the feed carries <itunes:season>
(American History Tellers has them; Explorers doesn't — it degrades to arc·date).

Usage:  python3 design/kit/build-detail.py
"""

import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCREENS = HERE / "screens"
DATA = HERE / "data"

ARCS_SHOWN = 10
EPISODES_SHOWN = 24

ICO_DL = ('<svg width="20" height="20" viewBox="0 0 24 24" fill="none"><path d="M12 3.5v10.5M12 14l-3.6-3.6M12 14l3.6-3.6" '
          'stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/><path '
          'd="M4.5 17.5v1.4c0 .9.7 1.6 1.6 1.6h11.8c.9 0 1.6-.7 1.6-1.6v-1.4" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>')
ICO_CHECK = ('<svg width="20" height="20" viewBox="0 0 24 24" fill="none"><path d="M4 12.5 9.5 18 20 6" '
             'stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>')
ICO_PLAY = '<svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M7 5.2v13.6L18.5 12z"/></svg>'
ICO_PLUS = '<svg width="18" height="18" viewBox="0 0 24 24" fill="none"><path d="M12 5v14M5 12h14" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>'
ICO_CHECK_SM = '<svg width="18" height="18" viewBox="0 0 24 24" fill="none"><path d="M4 12.5 9.5 18 20 6" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>'

DETAIL_CSS = """
  /* ---------- podcast detail ---------- */
  .back-btn { position: absolute; top: 58px; left: 12px; z-index: 26; width: 40px; height: 40px;
    border-radius: 50%; display: grid; place-items: center; border: none; cursor: pointer;
    background: var(--chip); color: var(--text); box-shadow: inset 0 0 0 .5px var(--hairline);
    transition: transform .3s var(--ease-spring); }
  .back-btn:active { transform: scale(.9); }
  .pd-head { display: flex; gap: var(--sp-4); align-items: flex-start; margin-top: var(--sp-2); }
  .pd-art { flex: none; width: 118px; height: 118px; border-radius: var(--r-md); background-size: cover;
    background-position: center; box-shadow: inset 0 0 0 .5px rgba(255,255,255,.16), 0 8px 20px -10px rgba(0,0,0,.6); }
  .pd-meta { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 5px; }
  .pd-cat { font-size: .72rem; font-weight: 800; color: var(--accent-2); text-transform: uppercase; letter-spacing: .07em; }
  .pd-title { font-size: 1.28rem; font-weight: 800; letter-spacing: -.02em; line-height: 1.15; }
  .pd-author { font-size: .88rem; font-weight: 600; color: var(--text-dim); }
  .pd-head .sub { align-self: flex-start; margin-top: var(--sp-1); }
  .pd-desc { margin-top: var(--sp-4); font-size: .88rem; line-height: 1.5; color: var(--text-dim); }
  .pd-desc .clip { display: -webkit-box; -webkit-line-clamp: 4; -webkit-box-orient: vertical; overflow: hidden; }
  .pd-desc.open .clip { -webkit-line-clamp: unset; }
  .pd-more { margin-top: 4px; background: none; border: none; color: var(--accent); font-weight: 800;
    font-size: .82rem; font-family: var(--font); cursor: pointer; padding: 0; }
  /* story-arcs / seasons shelf */
  .arc-rail { display: flex; gap: var(--sp-3); overflow-x: auto; scroll-snap-type: x mandatory;
    padding: 4px var(--gutter) 8px; margin: 0 calc(var(--gutter) * -1); scrollbar-width: none; }
  .arc-rail::-webkit-scrollbar { height: 0; }
  .arc-card { flex: none; width: 176px; scroll-snap-align: start; background: var(--surface);
    border-radius: var(--r-lg); box-shadow: var(--elev-list); padding: var(--sp-3);
    display: flex; flex-direction: column; gap: 8px; cursor: pointer;
    transition: box-shadow .25s var(--ease-soft); }
  .arc-card.active { box-shadow: var(--elev-list), inset 0 0 0 2px var(--accent); }
  .arc-cover { width: 100%; aspect-ratio: 16 / 10; border-radius: var(--r-sm); background-size: cover;
    background-position: center; position: relative; overflow: hidden;
    box-shadow: inset 0 0 0 .5px rgba(255,255,255,.14); }
  .arc-season { position: absolute; top: 8px; left: 8px; font-size: .68rem; font-weight: 800;
    padding: 3px 8px; border-radius: 999px; background: rgba(10,7,14,.62); color: #fff; backdrop-filter: blur(6px); }
  .arc-name { font-size: .92rem; font-weight: 800; letter-spacing: -.01em; line-height: 1.2; min-height: 2.3em;
    display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
  .arc-parts { font-size: .76rem; font-weight: 600; color: var(--text-dim); }
  .arc-add { margin-top: 2px; display: inline-flex; align-items: center; justify-content: center; gap: 6px;
    height: 34px; border: none; border-radius: var(--r-pill); cursor: pointer; font-family: var(--font);
    font-size: .8rem; font-weight: 800; color: var(--on-accent);
    background: linear-gradient(135deg, var(--accent), color-mix(in srgb, var(--accent) 55%, var(--accent-2)));
    transition: transform .2s var(--ease-spring), background .3s; }
  .arc-add:active { transform: scale(.94); }
  .arc-add.added { background: var(--chip); color: var(--accent-2); }
  .arc-add svg { flex: none; }
  /* episode rows */
  .ep { display: flex; gap: var(--sp-3); padding: var(--sp-4) 0; border-top: .5px solid var(--separator); }
  .ep:first-of-type { border-top: none; }
  .ep.ep-extra { display: none; }        /* deeper-feed rows: shown only when their arc is filtered */
  .ep.first-shown { border-top: none; }  /* first visible row in a filtered view */
  .ep-art { flex: none; width: 56px; height: 56px; border-radius: var(--r-sm); background-size: cover;
    background-position: center; box-shadow: inset 0 0 0 .5px rgba(255,255,255,.14); }
  .ep-body { flex: 1; min-width: 0; }
  .ep-title { font-size: .98rem; font-weight: 700; letter-spacing: -.01em; line-height: 1.25;
    display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
  .ep-meta { margin-top: 3px; font-size: .78rem; font-weight: 600; color: var(--text-dim); }
  .ep-arc { color: var(--accent-2); font-weight: 800; }
  .ep-ctls { display: flex; align-items: center; gap: var(--sp-2); margin-top: 10px; }
  .ep-btn { flex: none; width: 38px; height: 38px; border-radius: 50%; border: none; cursor: pointer;
    display: grid; place-items: center; background: var(--chip); color: var(--text-dim);
    transition: transform .25s var(--ease-spring), background .3s, color .3s; }
  .ep-btn:active { transform: scale(.88); }
  .ep-btn.play { color: var(--text); }
  .ep-dl .ico-done { display: none; }
  .ep-dl.done { background: color-mix(in srgb, var(--accent-2) 16%, transparent); color: var(--accent-2); }
  .ep-dl.done .ico-dl { display: none; }
  .ep-dl.done .ico-done { display: inline-flex; }
  .ep-add .ico-check { display: none; }
  .ep-add.added { background: color-mix(in srgb, var(--accent-2) 16%, transparent); color: var(--accent-2); }
  .ep-add.added .ico-plus { display: none; }
  .ep-add.added .ico-check { display: inline-flex; }
  .ep-played { margin-left: auto; align-self: center; font-size: .72rem; font-weight: 800; color: var(--accent-2);
    display: inline-flex; align-items: center; gap: 4px; }
  /* episodes-header filter chip */
  .sec-right { display: flex; align-items: center; gap: var(--sp-2); }
  .ep-filter { border: none; cursor: pointer; font-family: var(--font);
    font-size: .74rem; font-weight: 800; color: var(--accent-2);
    background: color-mix(in srgb, var(--accent-2) 15%, transparent);
    padding: 4px 10px; border-radius: var(--r-pill);
    display: inline-flex; align-items: center; gap: 6px; }
  .ep-filter[hidden] { display: none; }
  .ep-filter .ef-x { font-weight: 600; opacity: .8; }
"""

SCRIPT = """<script>
  const root = document.documentElement;
  const tt = document.getElementById('tt');
  const tgEmoji = document.getElementById('tgEmoji');
  const tgLabel = document.getElementById('tgLabel');
  root.setAttribute('data-theme', 'dark');
  tt.addEventListener('click', () => {
    const dark = root.getAttribute('data-theme') === 'dark';
    root.setAttribute('data-theme', dark ? 'light' : 'dark');
    tgEmoji.textContent = dark ? '\\u2600\\ufe0f' : '\\ud83c\\udf19';
    tgLabel.textContent = dark ? 'Light' : 'Dark';
  });
  // subscribe pill
  document.querySelectorAll('.sub').forEach(btn => {
    const txt = btn.querySelector('.txt');
    btn.addEventListener('click', () => {
      const done = btn.classList.toggle('done');
      if (txt) txt.textContent = done ? 'Subscribed' : 'Subscribe';
      btn.classList.remove('pulsing'); void btn.offsetWidth; btn.classList.add('pulsing');
    });
  });
  // "Add all" on an arc card -> confirm, and mark that arc's rows as queued
  document.querySelectorAll('.arc-add').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();               // don't also trigger the card's filter
      const added = btn.classList.toggle('added');
      btn.querySelector('.lbl').textContent = added ? 'Added' : ('Add all ' + btn.dataset.count);
      const arc = btn.dataset.arc;
      document.querySelectorAll('.ep-add[data-arc="' + CSS.escape(arc) + '"]').forEach(a => {
        a.classList.toggle('added', added);
      });
    });
  });
  // tap an arc card body -> filter the episode list to that arc; tap again to clear
  const epRows = document.querySelectorAll('.ep');
  const cards = document.querySelectorAll('.arc-card');
  const epFilter = document.querySelector('.ep-filter');
  const efName = document.querySelector('.ef-name');
  const epCount = document.querySelector('.sec-right .count');
  function applyFilter(arc){
    cards.forEach(c => c.classList.toggle('active', arc != null && c.dataset.arc === arc));
    let first = true;
    epRows.forEach(row => {
      if (arc == null){
        row.style.display = '';                 // fall back to CSS (ep-extra stays hidden)
        row.classList.remove('first-shown');
        return;
      }
      const show = row.dataset.arc === arc;
      row.style.display = show ? 'flex' : 'none';  // 'flex' overrides .ep-extra's display:none
      row.classList.toggle('first-shown', show && first);
      if (show) first = false;
    });
    if (arc == null){
      epFilter.hidden = true;
      if (epCount) epCount.hidden = false;
    } else {
      efName.textContent = arc;
      epFilter.hidden = false;
      if (epCount) epCount.hidden = true;
    }
  }
  cards.forEach(card => {
    const toggle = () => {
      const arc = card.dataset.arc;
      applyFilter(card.classList.contains('active') ? null : arc);
    };
    card.addEventListener('click', (e) => {
      if (e.target.closest('.arc-add')) return;   // let "Add all" do its own thing
      toggle();
    });
    card.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' '){ e.preventDefault(); toggle(); }
    });
  });
  if (epFilter) epFilter.addEventListener('click', () => applyFilter(null));
  // per-row compact controls
  document.querySelectorAll('.ep-dl').forEach(b => b.addEventListener('click', () => b.classList.toggle('done')));
  document.querySelectorAll('.ep-add').forEach(b => b.addEventListener('click', () => b.classList.toggle('added')));
  // description "more"
  document.querySelectorAll('.pd-more').forEach(m => m.addEventListener('click', () => {
    const d = m.closest('.pd-desc'); const open = d.classList.toggle('open');
    m.textContent = open ? 'Less' : 'More';
  }));
</script>"""


def esc(s: str) -> str:
    return (s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def dur(sec: int) -> str:
    m = sec // 60
    if m >= 60:
        return f"{m // 60}h {m % 60}m"
    return f"{m} min"


def scaffold():
    """Pull head+styles, chrome (theme toggle → statusbar), dock, and closing
    from up-next.html so the detail screen stays token-identical."""
    up = (SCREENS / "up-next.html").read_text()
    idx_style2 = up.index("</style>", up.index("</style>") + 1)
    head = up[:idx_style2]                       # through the 2nd <style> block, before its close
    after = up[idx_style2 + len("</style>"):]
    chrome = after[:after.index('<div class="content"')]      # theme toggle + phone/notch/screen/statusbar
    nav = up[up.index('<nav class="tabbar"'):up.index("</nav>") + len("</nav>")]
    nav = nav.replace(' active', '').replace(' aria-current="page"', '')  # detail is pushed; no tab active
    closing = up[up.index('<div class="home-ind">'):up.index("<script>")]
    return head, chrome, nav, closing


BACK_BTN = ('    <button class="back-btn" aria-label="Back">'
            '<svg width="22" height="22" viewBox="0 0 24 24" fill="none">'
            '<path d="M15 5l-7 7 7 7" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>'
            '</button>\n')


def arc_card(arc, art_slug):
    season = (f'<span class="arc-season">Season {arc["season"]}</span>' if arc.get("season") else "")
    name = esc(arc["name"])
    count = arc["parts"]
    return f'''        <div class="arc-card" data-arc="{esc(arc["name"])}" role="button" tabindex="0" aria-label="Filter episodes by {esc(arc["name"])}">
          <div class="arc-cover" style="background-image:url(../art/{art_slug}.jpg)">{season}</div>
          <div class="arc-name">{name}</div>
          <div class="arc-parts">{count} episode{"s" if count != 1 else ""}</div>
          <button class="arc-add" data-arc="{esc(arc["name"])}" data-count="{count}">
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none"><path d="M12 5v14M5 12h14" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"/></svg>
            <span class="lbl">Add all {count}</span>
          </button>
        </div>'''


def episode_row(ep, art_slug, state, extra=False):
    # title: episode title if present, else the raw title (singles)
    title = esc(ep["episodeTitle"] or ep["rawTitle"])
    bits = []
    if ep["arc"]:
        bits.append(f'<span class="ep-arc">{esc(ep["arc"])}</span>')
    if ep.get("season") and ep.get("episodeNumber"):
        bits.append(f'S{ep["season"]} · E{ep["episodeNumber"]}')
    elif ep.get("part"):
        bits.append(f'Part {ep["part"]}')
    if ep["date"]:
        bits.append(esc(ep["date"]))
    bits.append(dur(ep["durationSec"]))
    meta = " · ".join(bits)

    dl_cls = "ep-btn ep-dl done" if state.get("downloaded") else "ep-btn ep-dl"
    add_cls = "ep-btn ep-add added" if state.get("queued") else "ep-btn ep-add"
    play = (f'<button class="ep-btn play" aria-label="Play">{ICO_PLAY}</button>' if state.get("downloaded") else "")
    played = ('<span class="ep-played">✓ Played</span>' if state.get("played") else "")
    ep_cls = "ep ep-extra" if extra else "ep"
    return f'''      <div class="{ep_cls}" data-arc="{esc(ep["arc"] or "")}">
        <div class="ep-art" style="background-image:url(../art/{art_slug}.jpg)"></div>
        <div class="ep-body">
          <div class="ep-title">{title}</div>
          <div class="ep-meta">{meta}</div>
          <div class="ep-ctls">
            <button class="{dl_cls}" aria-label="Download"><span class="ico-dl">{ICO_DL}</span><span class="ico-done">{ICO_CHECK}</span></button>
            {play}
            <button class="{add_cls}" data-arc="{esc(ep["arc"] or "")}" aria-label="Add to Up Next"><span class="ico-plus">{ICO_PLUS}</span><span class="ico-check">{ICO_CHECK_SM}</span></button>
            {played}
          </div>
        </div>
      </div>'''


def state_for(i):
    # synthesize plausible per-user states across the visible rows (states are
    # user data, not feed data — safe to vary for the mock).
    return {
        "downloaded": i in (0, 1, 5, 9),
        "downloading": False,
        "queued": i in (1,),
        "played": i in (7, 12),
    }


def build(slug: str):
    data = json.loads((DATA / f"{slug}.json").read_text())
    show = data["show"]
    art = show["artworkSlug"]
    head, chrome, nav, closing = scaffold()
    head = head + DETAIL_CSS + "</style>"

    shown_arcs = {a["name"] for a in data["arcs"][:ARCS_SHOWN]}
    arcs = "\n".join(arc_card(a, art) for a in data["arcs"][:ARCS_SHOWN])
    # Default view = newest EPISODES_SHOWN rows. Also render (hidden) every deeper
    # episode that belongs to a shelf arc, so tapping any arc card filters to real
    # episodes. Feed order is preserved throughout.
    ep_rows = []
    for i, e in enumerate(data["episodes"]):
        default = i < EPISODES_SHOWN
        if default or e["arc"] in shown_arcs:
            ep_rows.append(episode_row(e, art, state_for(i), extra=not default))
    eps = "\n".join(ep_rows)
    cat = esc(show["category"] or "Podcast")
    desc = esc(show["summary"][:600].rstrip())

    content = f'''    <div class="content" id="content">

      <div class="pd-head">
        <div class="pd-art" style="background-image:url(../art/{art}.jpg)"></div>
        <div class="pd-meta">
          <div class="pd-cat">{cat}</div>
          <div class="pd-title">{esc(show["title"])}</div>
          <div class="pd-author">{esc(show["author"])}</div>
          <button class="sub" aria-pressed="false" aria-label="Subscribe to {esc(show["title"])}">
            <span class="ring"></span>
            <span class="ico ico-plus"><svg width="15" height="15" viewBox="0 0 13 13" fill="none"><path d="M6.5 1.5v10M1.5 6.5h10" stroke="currentColor" stroke-width="2.1" stroke-linecap="round"/></svg></span>
            <span class="ico ico-check"><svg width="15" height="15" viewBox="0 0 13 13" fill="none"><path d="M2 7l3 3 6-7" stroke="currentColor" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round"/></svg></span>
            <span class="txt">Subscribe</span>
          </button>
        </div>
      </div>

      <div class="pd-desc">
        <div class="clip">{desc}</div>
        <button class="pd-more">More</button>
      </div>

      <div class="sec-head" style="margin-top: var(--sp-5)">
        <h2>Story arcs</h2>
      </div>
      <!-- Arcs derived from episode titles ("Arc | Title | N" / "Arc - Part N"); season
           badge shows only when the feed carries <itunes:season>. "Add all" queues the
           whole arc in order. When a feed has neither arcs nor seasons, this shelf is omitted. -->
      <div class="arc-rail">
{arcs}
      </div>

      <div class="sec-head" style="margin-top: var(--sp-5)">
        <h2>Episodes</h2>
        <div class="sec-right">
          <span class="count">{data["counts"]["episodes"]}</span>
          <button class="ep-filter" hidden>Showing: <span class="ef-name"></span> <span class="ef-x">✕</span></button>
        </div>
      </div>
      <div class="eplist">
{eps}
      </div>

    </div>

'''
    html = head + "\n" + chrome + BACK_BTN + content + "    " + nav + "\n\n    " + closing + SCRIPT + "\n"
    # set the tab title
    html = re.sub(r'<title>[^<]*</title>', f'<title>{esc(show["title"])} · Detail</title>', html, count=1)
    out = SCREENS / f"podcast-detail-{slug}.html"
    out.write_text(html)
    print(f"wrote {out.relative_to(HERE.parent.parent)}  ({len(data['arcs'][:ARCS_SHOWN])} arcs, {len(ep_rows)} episode rows: {EPISODES_SHOWN} default + {len(ep_rows) - EPISODES_SHOWN} hidden arc rows)")


def main():
    for f in sorted(DATA.glob("*.json")):
        build(f.stem)


if __name__ == "__main__":
    main()

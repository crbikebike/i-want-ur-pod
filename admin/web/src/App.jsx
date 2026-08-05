import { useCallback, useEffect, useRef, useState } from "react";

/* The Catalog Roster Queue.
 *
 * The job: deciding who is on the roster. The catalog is meant to hold story-driven,
 * investigative shows and nothing else -- no host-interviews-guest talk shows. 315 were imported from an earlier list
 * and none has ever been checked against that standard, so Comedy, Sports and
 * Self-Improvement entries are in there right now. This is where each show is checked
 * and either stays in the catalog or does not.
 *
 * One show fills the screen. You keep it, cut it, or skip it. The card leaves carrying
 * the colour of what you chose, the count goes down, and the next one rises.
 *
 * Two things are load-bearing and easy to lose in a refactor:
 *
 *   The verdict is sent optimistically. Waiting on a round trip before animating makes
 *   a 90ms network feel like hesitation, and hesitation is what stops a queue getting
 *   cleared. If the request fails we say so and put the card back.
 *
 *   A skip is not a verdict. It writes nothing and is remembered only for this session,
 *   because "not now" is about the mood you are in, not a fact about the show.
 */

const UNDO_WINDOW = 10000;

export default function App() {
  const [counts, setCounts] = useState(null);
  const [item, setItem] = useState(null);
  const [done, setDone] = useState(false);
  const [error, setError] = useState(null);
  const [leaving, setLeaving] = useState(null); // 'keep' | 'cut' | 'skip'
  const [lastEdit, setLastEdit] = useState(null);
  const [session, setSession] = useState({ keep: 0, cut: 0, skip: 0 });
  const [preview, setPreview] = useState(null);   // the slid-up Apple player

  // Labels is a third, independent mode -- not a step in the feeds-then-inclusion
  // sequence, so its data lives apart from the state above rather than threaded through
  // `decide`/`load`, which are shaped around the two-queue handoff.
  const [labelCounts, setLabelCounts] = useState(null);
  const [vocab, setVocab] = useState(null); // {themes:[...]} -- fetched once per session

  const skipped = useRef([]);
  const undoTimer = useRef(null);

  /* Feeds first while any are waiting.
   *
   * Not a preference -- an ordering the data forces. Judging whether a show belongs is
   * meaningless while the row might be describing a different podcast, and that is exactly
   * how nineteen cuts landed on shows nobody had looked at. Clear the identity question,
   * then the taste question. */
  // #feeds / #inclusion / #labels in the URL picks the opening mode, so a phone can
  // bookmark the tab it lives in. The hash is read once; switching after load is state.
  const [mode, setMode] = useState(() => {
    const h = window.location.hash.replace("#", "");
    return ["feeds", "inclusion", "labels"].includes(h) ? h : "feeds";
  });

  // The switcher jumps modes directly rather than waiting for a queue to empty, so the
  // transient state from wherever you were needs clearing up front -- otherwise the old
  // card (or the old "all done" screen) flashes for one fetch cycle in the new mode.
  function switchMode(next) {
    if (next === mode) return;
    skipped.current = [];
    setItem(null);
    setDone(false);
    setError(null);
    setPreview(null);
    // The hash tracks the tab, so the reload iOS forces on a backgrounded tab (the OS
    // evicts it; nothing this app can prevent) comes back to the same mode instead of
    // falling to the default and auto-advancing somewhere else.
    window.location.hash = next;
    setMode(next);
  }

  // Fetched once per session, the first time the labels mode is opened, and kept here
  // (not inside LabelsQueue) so switching away and back doesn't re-fetch it.
  useEffect(() => {
    if (mode === "labels" && !vocab) {
      fetch("/api/vocabulary")
        .then((r) => r.json())
        .then(setVocab)
        .catch(() => {});
    }
  }, [mode, vocab]);

  const load = useCallback(async () => {
    try {
      const q = skipped.current.length ? `?skip=${skipped.current.join(",")}` : "";
      const r = await fetch(`/api/queues/${mode === "feeds" ? "feeds" : "inclusion"}${q}`);
      if (!r.ok) throw new Error(`the server said ${r.status}`);
      const data = await r.json();
      // An empty feed queue is not an empty session -- it means the identity questions are
      // settled and the taste questions are next. Falling through is what makes "feeds
      // first" an ordering rather than a mode the user has to know about.
      if (mode === "feeds" && !data.item) {
        // Clearing the item is not tidiness. The two queues carry different shapes, and
        // leaving the last feed card in state while the mode flips meant Card rendered it
        // and threw on show.links.map -- React unmounts the tree and the whole screen goes
        // blank, which is what "the all-finished screen is empty" actually was.
        skipped.current = [];
        setItem(null);
        setDone(false);
        setMode("inclusion");
        return;
      }
      setCounts(data.counts);
      setItem(data.item);
      setDone(!data.item);
      setError(null);
    } catch (e) {
      setError(e.message);
    }
  }, [mode]);

  useEffect(() => { load(); }, [load]);

  useEffect(() => () => clearTimeout(undoTimer.current), []);

  function armUndo(edit) {
    clearTimeout(undoTimer.current);
    setLastEdit(edit);
    undoTimer.current = setTimeout(() => setLastEdit(null), UNDO_WINDOW);
  }

  /* Confirming a feed repoints the show and pulls its episodes, which is a real write and
   * can genuinely fail -- the feed may be down. So unlike a verdict it is NOT sent
   * optimistically: the card waits. A false green here would tell you a broken row was
   * fixed when it was not, and that is the failure this whole queue exists to undo. */
  async function decideFeed(decision) {
    if (!item || leaving) return;
    const card = item;

    if (decision === "skip") {
      skipped.current = [...skipped.current, card.id];
      setLeaving("skip");
      setSession((s) => ({ ...s, skip: s.skip + 1 }));
      setTimeout(load, 300);
      setTimeout(() => setLeaving(null), 340);
      return;
    }

    setLeaving(decision === "confirmed" ? "keep" : "cut");
    try {
      const r = await fetch(`/api/queues/feeds/${card.id}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ decision }),
      });
      if (!r.ok) throw new Error((await r.json()).detail || `the server said ${r.status}`);
      const data = await r.json();
      setCounts(data.counts);
      setSession((s) => ({ ...s, [decision === "confirmed" ? "keep" : "cut"]: s[decision === "confirmed" ? "keep" : "cut"] + 1 }));
      setLeaving(null);
      load();
    } catch (e) {
      setError(`${card.title} was not repointed — ${e.message}`);
      setLeaving(null);
    }
  }

  async function decide(verdict) {
    if (!item || leaving) return;
    const show = item;

    // Animate first. The decision already happened in your head; the UI should agree.
    setLeaving(verdict);
    setPreview(null);
    setSession((s) => ({ ...s, [verdict]: s[verdict] + 1 }));

    if (verdict === "skip") {
      skipped.current = [...skipped.current, show.id];
      armUndo({ kind: "skip", title: show.title, id: show.id });
    }

    setTimeout(load, 300);
    setTimeout(() => setLeaving(null), 340);

    if (verdict === "skip") return;

    try {
      const r = await fetch(`/api/queues/inclusion/${show.id}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ verdict }),
      });
      if (!r.ok) throw new Error((await r.json()).detail || `the server said ${r.status}`);
      const data = await r.json();
      setCounts(data.counts);
      armUndo({ kind: verdict, title: show.title, editId: data.editId });
    } catch (e) {
      // Put it back rather than pretending. A silently-lost verdict is the one failure
      // that would make the whole log untrustworthy.
      setError(`${show.title} was not saved — ${e.message}`);
      setSession((s) => ({ ...s, [verdict]: s[verdict] - 1 }));
      load();
    }
  }

  async function undo() {
    const e = lastEdit;
    if (!e) return;
    clearTimeout(undoTimer.current);
    setLastEdit(null);
    setSession((s) => ({ ...s, [e.kind]: Math.max(0, s[e.kind] - 1) }));

    if (e.kind === "skip") {
      skipped.current = skipped.current.filter((id) => id !== e.id);
      load();
      return;
    }
    try {
      const r = await fetch(`/api/edits/${e.editId}/undo`, { method: "POST" });
      if (!r.ok) throw new Error(`the server said ${r.status}`);
      setCounts((await r.json()).counts);
      load();
    } catch (err) {
      setError(`could not undo — ${err.message}`);
    }
  }

  /* Keyboard, for clearing a queue at a desk.
   *
   * Letters are mnemonic and arrows follow the buttons' left-to-right order, so the
   * hand can use whichever it reaches for. Both are printed on the buttons -- a
   * shortcut nobody can see is one nobody uses.
   *
   * Two guards worth keeping. Space is skip, but Space also activates a focused
   * button; without the target check, tabbing to Keep and pressing Space would keep
   * AND skip. And any modifier is ignored, so browser and OS chords still work --
   * except Cmd/Ctrl+Z, which everyone's fingers already know means undo.
   */
  useEffect(() => {
    const onKey = (ev) => {
      const typing = /^(INPUT|TEXTAREA|SELECT)$/.test(ev.target.tagName) || ev.target.isContentEditable;
      if (typing) return;

      // Labels has its own verdict shapes (confirm/skip/change, not keep/cut/skip) and
      // no keyboard affordance in the design -- this is a phone-over-the-tailnet queue.
      // Bail rather than let Y/C/R/arrows fire the inclusion queue's `decide` against
      // whatever `item` is left over from the last non-labels mode.
      if (mode === "labels") return;

      if (ev.key === "Escape") { setPreview(null); return; }
      if ((ev.metaKey || ev.ctrlKey) && ev.key.toLowerCase() === "z") {
        ev.preventDefault();
        undo();
        return;
      }
      if (ev.metaKey || ev.ctrlKey || ev.altKey) return;

      const onAButton = ev.target.tagName === "BUTTON";
      const key = ev.key.toLowerCase();

      // Same three positions in both queues -- right is the affirmative one, left is the
      // negative one, space is "not now" -- so the hand does not have to know which
      // question is on screen.
      const act = mode === "feeds" ? decideFeed : decide;
      const yes = mode === "feeds" ? "confirmed" : "keep";
      const no = mode === "feeds" ? "rejected" : "cut";

      if (key === "k" || key === "y" || ev.key === "ArrowRight") act(yes);
      else if (key === "c" || key === "r" || ev.key === "ArrowLeft") act(no);
      else if (key === "s" || (ev.key === " " && !onAButton)) { ev.preventDefault(); act("skip"); }
      else if (key === "u" && mode !== "feeds") undo();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  });

  const total = counts?.total ?? 0;
  const settled = counts ? counts.decided : 0;

  return (
    <div className="app">
      <header className="head">
        <h1>{mode === "feeds" ? "Right Show?" : mode === "inclusion" ? "Catalog Roster Queue" : "Labels"}</h1>
        {mode !== "labels" && counts && (
          <div className="left">
            <b>{counts.waiting}</b> to go
          </div>
        )}
        {mode === "labels" && (
          <div className="left labels-note">
            <p className="hint">sampled, lowest agreement first — there is no count and no bottom</p>
            {/* Quiet on purpose: a running tally of today's work, never a total or a
                remaining count -- see the design note above. */}
            {labelCounts && <p className="quiet">{labelCounts.reviewedToday} reviewed today</p>}
          </div>
        )}
      </header>

      <nav className="modes" aria-label="Workbench mode">
        {[["feeds", "Feeds"], ["inclusion", "Roster"], ["labels", "Labels"]].map(([m, label]) => (
          <button key={m} className={mode === m ? "on" : ""} onClick={() => switchMode(m)}>
            {label}
          </button>
        ))}
      </nav>

      <div className={`track${mode === "labels" ? " off" : ""}`}>
        {mode !== "labels" && (
          <span style={{ width: total ? `${(settled / total) * 100}%` : "0%" }} />
        )}
      </div>

      {mode === "labels" ? (
        <LabelsQueue vocab={vocab} onCounts={setLabelCounts} />
      ) : (
        <>
          <main className="stage">
            {error && <div className="err">{error}</div>}
            {!error && done && <Finished session={session} counts={counts} />}
            {!error && !done && !item && <Loading />}
            {!error && item && mode === "feeds" && (
              <FeedCard key={item.id} item={item} leaving={leaving} onPreview={setPreview} />
            )}
            {!error && item && mode !== "feeds" && (
              <Card key={item.id} show={item} leaving={leaving} onPreview={setPreview} />
            )}
          </main>

          {preview && <Preview link={preview} onClose={() => setPreview(null)} />}

          <div className="toast">
            <div className={`undo ${lastEdit ? "" : "gone"}`}>
              <span className={`what ${lastEdit?.kind ?? ""}`}>
                <b>{lastEdit?.kind === "skip" ? "Skipped" : lastEdit?.kind === "cut" ? "Cut" : "Kept"}</b>
                {" "}{lastEdit?.title}
              </span>
              <button onClick={undo}>Undo</button>
            </div>
            <div className="verdicts">
              {mode === "feeds" ? (
                <>
                  <Verdict kind="cut" label="Not it" keys="R" onPick={() => decideFeed("rejected")}
                           disabled={!item || !!leaving} />
                  <Verdict kind="skip" label="Skip" keys="S" onPick={() => decideFeed("skip")}
                           disabled={!item || !!leaving} />
                  <Verdict kind="keep" label="That's it" keys="Y" onPick={() => decideFeed("confirmed")}
                           disabled={!item || !!leaving} />
                </>
              ) : (
                <>
                  <Verdict kind="cut" label="Cut" keys="C" onPick={decide} disabled={!item || !!leaving} />
                  <Verdict kind="skip" label="Skip" keys="S" onPick={decide} disabled={!item || !!leaving} />
                  <Verdict kind="keep" label="Keep" keys="K" onPick={decide} disabled={!item || !!leaving} />
                </>
              )}
            </div>
          </div>
        </>
      )}
    </div>
  );
}

/* Apple's embed player, slid up in place.
 *
 * Their ordinary pages are X-Frame-Options: DENY; the embed is not, and it carries the
 * description, episode list and playable previews -- which is the whole question. It
 * stops above the verdict buttons, so you can listen and then decide without dismissing
 * anything.
 *
 * I could not verify it paints in headless Chrome -- it shows only Apple's placeholder
 * there, twice, on both URL forms and both origins, which is probably the missing media
 * stack rather than a real failure. Since I could not prove it, the sheet says so after
 * a few seconds and offers the tab instead. A blank grey box with no way out would be
 * worse than the new tab this replaced.
 */
function Preview({ link, onClose }) {
  const [slow, setSlow] = useState(false);
  useEffect(() => {
    const t = setTimeout(() => setSlow(true), 3500);
    return () => clearTimeout(t);
  }, []);

  return (
    <>
      <button className="scrim" onClick={onClose} aria-label="Close preview" />
      <section className="sheet" role="dialog" aria-label="Preview">
        <header>
          <span className="grab" aria-hidden="true" />
          <a href={link.href} target="_blank" rel="noreferrer">Open in Apple ↗</a>
          <button onClick={onClose}>Close</button>
        </header>
        <div className="frame">
          <iframe
            title="Apple Podcasts preview"
            src={link.embed}
            allow="autoplay *; encrypted-media *;"
            sandbox="allow-forms allow-popups allow-same-origin allow-scripts allow-storage-access-by-user-activation"
          />
          {slow && (
            <p className="stuck">
              Not loading? <a href={link.href} target="_blank" rel="noreferrer">Open it in Apple Podcasts ↗</a>
            </p>
          )}
        </div>
      </section>
    </>
  );
}

/* The key hint is rendered but hidden on touch devices, where it would be a lie. */
function Verdict({ kind, label, keys, onPick, disabled }) {
  return (
    <button
      className={`v ${kind}`}
      onClick={() => onPick(kind)}
      disabled={disabled}
      aria-keyshortcuts={keys}
      title={`${label} (${keys})`}
    >
      <span>{label}</span>
      <kbd>{keys}</kbd>
    </button>
  );
}

/* Is this row even about the show it claims to be?
 *
 * A question that has to be settled before "does it belong?" means anything. Twenty-seven
 * rows served a different podcast, and nineteen cuts and eight keeps were recorded against
 * shows nobody was looking at.
 *
 * The card is two columns because the decision is a comparison. On the left, what the
 * catalog believes. On the right, what the feed actually contains -- and the episode
 * titles are the part that settles it. Publisher names argue; "7 Hebrew Words for Praise"
 * against "a true-crime docuseries about April Balascio" does not.
 */
function FeedCard({ item, leaving, onPreview }) {
  const c = item.candidate;
  return (
    <article className={`card arriving ${leaving ? `leaving ${leaving}` : ""}`}>
      <div className="top">
        <div>
          <h2 className="title">{item.title}</h2>
          <p className="by">{[item.network, item.years].filter(Boolean).join(" · ")}</p>
        </div>
      </div>

      <div className="compare">
        <div className="side">
          <b>The catalog says</b>
          <p>{item.claims.description}</p>
        </div>
        <div className="side cand">
          <b>This feed says</b>
          <p className="feedname">{c.title}</p>
          <p className="author">{c.author || "no publisher named"} · {c.episodeCount} episodes</p>
          <ul className="eps">
            {c.sample.map((t, i) => <li key={i}>{t}</li>)}
          </ul>
        </div>
      </div>

      <div className="links">
        {(item.links || []).map((l) =>
          l.embed ? (
            <button key={l.href} className="go" onClick={() => onPreview(l)}>
              {l.label} <span aria-hidden="true">▴</span>
            </button>
          ) : (
            <a key={l.href} href={l.href} target="_blank" rel="noreferrer" className="go">
              {l.label} <span aria-hidden="true">↗</span>
            </a>
          )
        )}
      </div>

      <p className="means">{item.meaning}</p>
    </article>
  );
}

function Card({ show, leaving, onPreview }) {
  return (
    <article className={`card arriving ${leaving ? `leaving ${leaving}` : ""}`}>
      <div className="top">
        {show.artwork && (
          <img className="art" src={show.artwork} alt="" loading="lazy"
               onError={(e) => { e.currentTarget.style.display = "none"; }} />
        )}
        <div>
          <h2 className="title">{show.title}</h2>
          <p className="by">{[show.network, show.years].filter(Boolean).join(" · ")}</p>
        </div>
      </div>

      {show.note && (
        <div className={`note ${show.note.tone}`}>
          <b>{show.note.label}</b>
          {show.note.detail.map((d) => <p key={d}>{d}</p>)}
          <p className="means">{show.note.meaning}</p>
        </div>
      )}

      {show.assessment && <Assessment fit={show.assessment} />}

      <div className="links">
        {show.links.map((l) =>
          l.embed ? (
            <button key={l.href} className="go" onClick={() => onPreview(l)}>
              {l.label} <span aria-hidden="true">▴</span>
            </button>
          ) : (
            <a key={l.href} href={l.href} target="_blank" rel="noreferrer" className="go">
              {l.label} <span aria-hidden="true">↗</span>
            </a>
          )
        )}
      </div>
    </article>
  );
}

/* What the fit agent made of this show, and why.
 *
 * The reason is the whole reason this block exists. Every show in this queue was read
 * once already; without the reasoning that read is just a label you either trust or
 * ignore, and neither makes the next decision faster. With it, the card is arguing a
 * case you can check against the Apple page one tap away.
 *
 * The verdict is a chip and the confidence is spelled out next to it in words -- "a
 * guess" carries the caveat that `low` does not. Nothing here is green or red; see
 * queues._assessment for why that matters.
 */
function Assessment({ fit }) {
  return (
    <div className="fit">
      <b>
        Assessed <span className={`chip ${fit.verdict}`}>{fit.verdict}</span>
        <i>{fit.sure}</i>
      </b>
      <p className="why">{fit.reason}</p>
      <p className="means">{fit.meaning}</p>
    </div>
  );
}

function Loading() {
  return <div className="state"><p>Finding the next one…</p></div>;
}

function Finished({ session, counts }) {
  const did = session.keep + session.cut;
  return (
    <div className="state">
      <div className="big">✓</div>
      <h2>{did ? "Nothing left waiting" : "All caught up"}</h2>
      <p>
        {did
          ? "Every show has a verdict. Skipped ones come back next time you open this."
          : "There is nothing in this queue right now."}
      </p>
      {did > 0 && (
        <div className="tally">
          kept {session.keep} · cut {session.cut}
          {session.skip > 0 && ` · skipped ${session.skip}`}
        </div>
      )}
      {counts && <div className="tally">{counts.kept} kept and {counts.cut} cut in all</div>}
    </div>
  );
}

/* The label queue: checking the arc-cascade's subject guess against what the episode is
 * actually about, one episode at a time, sampled lowest-agreement-first.
 *
 * It is its own small state machine rather than a branch of `decide`/`load` above. Those
 * two are shaped around a queue that gates the next one (feeds must clear before
 * inclusion starts) and a verdict vocabulary (keep/cut/skip) that doesn't fit here --
 * confirm and change both write through the edits door, but "change" first has to open a
 * sheet and let you find the right subject out of 148, which the other queues never do.
 * Keeping it separate meant the feeds/inclusion code above didn't have to grow a branch
 * for a shape it doesn't share.
 *
 * Confirm is sent optimistically, same reasoning as `decide` above: the verdict already
 * happened in your head, and the round trip is small. Skip writes nothing, same as
 * everywhere else -- "not now" is a mood, not a fact about the label. Change waits for a
 * subject to be picked in the sheet before it sends anything.
 */
function LabelsQueue({ vocab, onCounts }) {
  const [counts, setCounts] = useState(null);
  const [item, setItem] = useState(null);
  const [error, setError] = useState(null);
  const [leaving, setLeaving] = useState(null); // 'keep' (confirm) | 'cut' (change) | 'skip'
  const [sheetOpen, setSheetOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [flashSlug, setFlashSlug] = useState(null);

  const skipped = useRef([]);

  const load = useCallback(async () => {
    try {
      const q = skipped.current.length ? `?skip=${skipped.current.join(",")}` : "";
      const r = await fetch(`/api/queues/labels${q}`);
      if (!r.ok) throw new Error(`the server said ${r.status}`);
      const data = await r.json();
      setCounts(data.counts);
      onCounts(data.counts);
      setItem(data.item);
      setError(null);
      // The card in hand survives the reload iOS forces on evicted tabs. Sampling is
      // random within an agreement band, so without this, stepping out to research an
      // episode comes back to a different one -- which punishes exactly the person
      // doing the job carefully.
      if (data.item) {
        localStorage.setItem("labelqueue.card",
          JSON.stringify({ item: data.item, at: Date.now() }));
      }
    } catch (e) {
      setError(e.message);
    }
  }, [onCounts]);

  useEffect(() => {
    // Restore the pre-eviction card if it is fresh enough that the person is plausibly
    // mid-research (45 minutes). A card decided elsewhere in the meantime re-serves
    // once, and re-deciding it is harmless -- same door, same value.
    try {
      const saved = JSON.parse(localStorage.getItem("labelqueue.card") || "null");
      if (saved?.item && Date.now() - saved.at < 45 * 60 * 1000) {
        setItem(saved.item);
        return;
      }
    } catch { /* a corrupt saved card is just a cache miss */ }
    load();
  }, [load]);

  async function confirm() {
    if (!item || leaving) return;
    const card = item;
    setLeaving("keep");
    setTimeout(() => setLeaving(null), 340);
    setTimeout(load, 300);
    try {
      const r = await fetch(`/api/queues/labels/${card.episodeId}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "confirm" }),
      });
      if (!r.ok) throw new Error((await r.json()).detail || `the server said ${r.status}`);
      const data = await r.json();
      setCounts(data.counts);
      onCounts(data.counts);
    } catch (e) {
      setError(`${card.title} was not confirmed — ${e.message}`);
    }
  }

  function skip() {
    if (!item || leaving) return;
    skipped.current = [...skipped.current, item.episodeId];
    setLeaving("skip");
    setTimeout(() => setLeaving(null), 340);
    setTimeout(load, 300);
  }

  function openSheet() {
    if (!item || leaving) return;
    setQuery("");
    setSheetOpen(true);
  }

  async function change(subject) {
    if (!item) return;
    const card = item;
    // Picking is the verdict, so it flashes green in the sheet for a beat before the
    // sheet closes and the card carries the colour the rest of the way out.
    setFlashSlug(subject);
    setTimeout(async () => {
      setFlashSlug(null);
      setSheetOpen(false);
      setLeaving("cut");
      setTimeout(() => setLeaving(null), 340);
      setTimeout(load, 300);
      try {
        const r = await fetch(`/api/queues/labels/${card.episodeId}`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ action: "change", subject }),
        });
        if (!r.ok) throw new Error((await r.json()).detail || `the server said ${r.status}`);
        const data = await r.json();
        setCounts(data.counts);
        onCounts(data.counts);
      } catch (e) {
        setError(`${card.title} was not changed — ${e.message}`);
      }
    }, 420);
  }

  return (
    <>
      <main className="stage">
        {error && <div className="err">{error}</div>}
        {!error && !item && (
          <div className="state"><p>{counts ? "Nothing sampled right now" : "Finding the next one…"}</p></div>
        )}
        {!error && item && <LabelCard key={item.episodeId} item={item} leaving={leaving} />}
      </main>

      <div className="toast">
        <div className="verdicts">
          <button className="v keep" disabled={!item || !!leaving} onClick={confirm}>
            <span>Confirm</span><small>the label stands</small>
          </button>
          <button className="v skip" disabled={!item || !!leaving} onClick={skip}>
            <span>Skip</span><small>decide later</small>
          </button>
          <button className="v cut" disabled={!item || !!leaving} onClick={openSheet}>
            <span>Change</span><small>pick the right subject</small>
          </button>
        </div>
      </div>

      {sheetOpen && item && (
        <>
          <button className="scrim" onClick={() => setSheetOpen(false)} aria-label="Close" />
          <SubjectSheet
            item={item}
            vocab={vocab}
            query={query}
            setQuery={setQuery}
            flashSlug={flashSlug}
            onPick={change}
          />
        </>
      )}
    </>
  );
}

/* Strips markup down to the text a listener would actually hear read aloud. Feed
 * descriptions are HTML (Apple's own field is), and the workbench has no sanitiser
 * dependency and no other mode that renders feed HTML as HTML -- Card and FeedCard above
 * both print description fields straight into a <p>, i.e. as plain text. DOMParser here
 * follows that same rule: it never attaches the parsed nodes to the live document, so
 * nothing in the string executes: it's just the fastest correct way to un-escape entities
 * and drop tags. */
function htmlToText(html) {
  if (!html) return "";
  return new DOMParser().parseFromString(html, "text/html").body.textContent || "";
}

function LabelCard({ item, leaving }) {
  const p = item.primary;
  const agreement = p?.agreement ?? 0;
  const votes = p?.votes ?? 0;
  return (
    <article className={`card arriving ${leaving ? `leaving ${leaving}` : ""}`}>
      <p className="show">{item.show}</p>
      <h2 className="title">{item.title}</h2>
      <p className="when">{item.published}{item.arc ? ` · arc: ${item.arc}` : ""}</p>
      <p className="desc">{htmlToText(item.description)}</p>

      <div className="read">
        <p className="k">The machine's read</p>
        <div className="primary-line">
          <span className="chip">{p?.slug}</span>
          <span className="pips">
            <b>{"●".repeat(agreement)}</b>
            {"○".repeat(Math.max(votes - agreement, 0))}
            {" "}{agreement} of {votes} agreed
          </span>
          {typeof p?.confidence === "number" && (
            <span className="conf">{Math.round(p.confidence * 100)}% confidence</span>
          )}
        </div>
        {item.secondaries?.length > 0 && (
          <p className="scatter">also suggested: {item.secondaries.join(" · ")}</p>
        )}
      </div>
    </article>
  );
}

/* The change-subject sheet: quick-picks from the voters' own scatter and this show's
 * usual shelves first (item.likely), then the full 148 underneath, searchable and grouped
 * by theme. Filtering hides rather than disables -- a theme heading over zero matches
 * reads as a bug, not as "nothing here yet". */
function SubjectSheet({ item, vocab, query, setQuery, flashSlug, onPick }) {
  const q = query.trim().toLowerCase();
  const themes = vocab?.themes ?? [];
  const total = themes.reduce((n, t) => n + t.subjects.length, 0);
  // While searching, the phone keyboard owns the bottom half of the screen, so the
  // sheet grows full-height and the quick picks fold away -- otherwise results render
  // straight into the keyboard. Blur with an empty query folds it back; blur with a
  // query keeps the tall layout, because the person is reading results.
  const [searching, setSearching] = useState(false);

  return (
    <section className={`sheet picker${searching || q ? " searching" : ""}`}
             role="dialog" aria-label="Pick the right subject">
      <span className="grab" aria-hidden="true" />
      <div className="sheet-head">
        <p className="k">Most likely — the voters' scatter, then this show's shelves</p>
        <div className="likely">
          {(item.likely ?? []).map((l) => (
            <button key={l.slug} onClick={() => onPick(l.slug)}>
              {l.name || l.slug}
              {l.note && <small>{l.note}</small>}
            </button>
          ))}
        </div>
        <div className="search">
          <input
            type="search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onFocus={() => setSearching(true)}
            onBlur={() => { if (!query.trim()) setSearching(false); }}
            placeholder={`search all ${total || 199} — name, slug or definition`}
          />
        </div>
      </div>
      <div className="subjects">
        {themes.map((theme) => {
          const subjects = q
            ? theme.subjects.filter((s) =>
                `${s.name} ${s.slug} ${s.description}`.toLowerCase().includes(q))
            : theme.subjects;
          if (q && subjects.length === 0) return null;
          return (
            <div key={theme.slug}>
              <p className="theme-label">{theme.name}</p>
              {subjects.map((s) => (
                <button
                  key={s.slug}
                  className={`subj${flashSlug === s.slug ? " picked" : ""}`}
                  onClick={() => onPick(s.slug)}
                >
                  <span className="nm">{s.name}</span>
                  <span className="sl">{s.slug}</span>
                  <p className="df">{s.description}</p>
                </button>
              ))}
            </div>
          );
        })}
      </div>
    </section>
  );
}

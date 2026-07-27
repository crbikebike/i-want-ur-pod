import { useCallback, useEffect, useRef, useState } from "react";

/* The inclusion queue.
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

  const skipped = useRef([]);
  const undoTimer = useRef(null);

  const load = useCallback(async () => {
    try {
      const q = skipped.current.length ? `?skip=${skipped.current.join(",")}` : "";
      const r = await fetch(`/api/queues/inclusion${q}`);
      if (!r.ok) throw new Error(`the server said ${r.status}`);
      const data = await r.json();
      setCounts(data.counts);
      setItem(data.item);
      setDone(!data.item);
      setError(null);
    } catch (e) {
      setError(e.message);
    }
  }, []);

  useEffect(() => { load(); }, [load]);

  useEffect(() => () => clearTimeout(undoTimer.current), []);

  function armUndo(edit) {
    clearTimeout(undoTimer.current);
    setLastEdit(edit);
    undoTimer.current = setTimeout(() => setLastEdit(null), UNDO_WINDOW);
  }

  async function decide(verdict) {
    if (!item || leaving) return;
    const show = item;

    // Animate first. The decision already happened in your head; the UI should agree.
    setLeaving(verdict);
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

      if ((ev.metaKey || ev.ctrlKey) && ev.key.toLowerCase() === "z") {
        ev.preventDefault();
        undo();
        return;
      }
      if (ev.metaKey || ev.ctrlKey || ev.altKey) return;

      const onAButton = ev.target.tagName === "BUTTON";
      const key = ev.key.toLowerCase();

      if (key === "k" || ev.key === "ArrowRight") decide("keep");
      else if (key === "c" || ev.key === "ArrowLeft") decide("cut");
      else if (key === "s" || (ev.key === " " && !onAButton)) { ev.preventDefault(); decide("skip"); }
      else if (key === "u") undo();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  });

  const total = counts?.total ?? 0;
  const settled = counts ? counts.decided : 0;

  return (
    <div className="app">
      <header className="head">
        <h1>Does it belong?</h1>
        {counts && (
          <div className="left">
            <b>{counts.waiting}</b> to go
          </div>
        )}
      </header>

      <div className="track">
        <span style={{ width: total ? `${(settled / total) * 100}%` : "0%" }} />
      </div>

      <main className="stage">
        {error && <div className="err">{error}</div>}
        {!error && done && <Finished session={session} counts={counts} />}
        {!error && !done && !item && <Loading />}
        {!error && item && (
          <Card key={item.id} show={item} leaving={leaving} />
        )}
      </main>

      <div className="toast">
        <div className={`undo ${lastEdit ? "" : "gone"}`}>
          <span className={`what ${lastEdit?.kind ?? ""}`}>
            <b>{lastEdit?.kind === "skip" ? "Skipped" : lastEdit?.kind === "cut" ? "Cut" : "Kept"}</b>
            {" "}{lastEdit?.title}
          </span>
          <button onClick={undo}>Undo</button>
        </div>
        <div className="verdicts">
          <Verdict kind="cut" label="Cut" keys="C" onPick={decide} disabled={!item || !!leaving} />
          <Verdict kind="skip" label="Skip" keys="S" onPick={decide} disabled={!item || !!leaving} />
          <Verdict kind="keep" label="Keep" keys="K" onPick={decide} disabled={!item || !!leaving} />
        </div>
      </div>
    </div>
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

function Card({ show, leaving }) {
  return (
    <article className={`card arriving ${leaving ? `leaving ${leaving}` : ""}`}>
      {show.flagged && show.evidence.length > 0 && (
        <div className="flag">
          <b>Flagged</b>
          <ul>{show.evidence.map((e) => <li key={e}>{e}</li>)}</ul>
        </div>
      )}

      <div className="top">
        {/* Artwork is a nice-to-have and 20 shows have none. A broken-image box would
            be worse than no image, so a failed load removes itself. */}
        {show.artwork && (
          <img
            className="art"
            src={show.artwork}
            alt=""
            loading="lazy"
            onError={(e) => { e.currentTarget.style.display = "none"; }}
          />
        )}
        <div>
          <h2 className="title">{show.title}</h2>
          <p className="by">
            {[show.network, show.years].filter(Boolean).join(" · ")}
          </p>
        </div>
      </div>

      {show.pitch && <p className="pitch">{show.pitch}</p>}
      {show.description && <p className="blurb">{show.description}</p>}

      <div className="facts">
        <span className="fact">{show.episodeCount.toLocaleString()} episodes</span>
        {show.arcCount > 0 && <span className="fact arcs">{show.arcCount} arcs</span>}
        {show.category && <span className="fact">{show.category}</span>}
        {show.lang !== "en" && <span className="fact">{show.lang}</span>}
        {show.themes.map((t) => <span className="fact" key={t}>{t}</span>)}
      </div>

      {show.recentEpisodes.length > 0 && (
        <div className="sec">
          <h2>Most recent episodes</h2>
          <ul className="eps">
            {show.recentEpisodes.map((e, i) => <li key={i}>{e}</li>)}
          </ul>
        </div>
      )}

      {show.subjects.length > 0 && (
        <div className="sec">
          <h2>What its episodes are about</h2>
          <div className="facts">
            {show.subjects.map((s) => <span className="fact" key={s}>{s}</span>)}
          </div>
        </div>
      )}
    </article>
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

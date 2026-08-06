"""The catalog workbench.

    uvicorn admin.api.main:app --host 100.117.245.23 --port 8828

Binds to hfab's Tailscale address, never 0.0.0.0. There is no login because the tailnet
is the boundary: reaching this at all means being on Chris's network. Binding it wider
would turn that from a reasonable posture into a wide-open catalog editor.
"""

from __future__ import annotations

import os
import sqlite3
import subprocess
import urllib.parse
from contextlib import contextmanager
from pathlib import Path

from fastapi import Body, FastAPI, HTTPException
from fastapi.responses import FileResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles

from admin.api import apple, auto, edits, feedqueue, feeds, labelqueue, queues, repair, vocab
from catalog.build import migrations

ROOT = Path(__file__).resolve().parents[2]
DB = Path(os.environ.get("CATALOG_DB", ROOT / "catalog/catalog.db"))
WEB_DIST = ROOT / "admin/web/dist"

app = FastAPI(title="catalog workbench", docs_url="/api/docs", redoc_url=None)


@contextmanager
def db():
    conn = sqlite3.connect(DB, timeout=10)
    conn.execute("PRAGMA foreign_keys = ON")
    try:
        yield conn
    finally:
        conn.close()


@app.on_event("startup")
def _startup() -> None:
    if not DB.exists():
        raise RuntimeError(
            f"no catalog at {DB}. Import one first: python -m catalog.build.migrate"
        )
    with db() as conn:
        conn.execute("PRAGMA journal_mode = WAL")
        for line in migrations.apply_all(conn).lines():
            print(line)
        # Settle anything with a foregone conclusion before a human is shown a queue of
        # questions that includes answers.
        for line in auto.resolve(conn).lines():
            print(line)


# --- the inclusion queue ---------------------------------------------------------


@app.get("/api/queues/inclusion")
def inclusion(skip: str = "") -> dict:
    """The next show to judge, plus how much is left.

    `skip` is a comma-separated list of ids the client has skipped this session. Skips
    are deliberately not persisted: a skip means "not now", and next time is a different
    session with a different mood.
    """
    skipped = [int(s) for s in skip.split(",") if s.strip().isdigit()]
    with db() as conn:
        return {
            "counts": queues.inclusion_counts(conn),
            "item": queues.inclusion_next(conn, skipped),
        }


@app.post("/api/queues/inclusion/{show_id}")
def judge(show_id: int, body: dict = Body(...)) -> dict:
    verdict = body.get("verdict")
    if verdict not in queues.VERDICTS:
        raise HTTPException(400, f"verdict must be one of {sorted(queues.VERDICTS)}")
    with db() as conn:
        try:
            edit = edits.apply(
                conn, entity_type="show", entity_id=show_id,
                field="include_verdict", after=verdict, note=body.get("note"),
            )
        except edits.EditError as e:
            raise HTTPException(400, str(e))
        return {"editId": edit.edit_id, "counts": queues.inclusion_counts(conn)}


# --- the feed queue ---------------------------------------------------------------


@app.get("/api/queues/feeds")
def feed_queue(skip: str = "") -> dict:
    """A row that points at the wrong podcast, and the best candidate for the right one."""
    skipped = [int(s) for s in skip.split(",") if s.strip().isdigit()]
    with db() as conn:
        return {
            "counts": feedqueue.counts(conn),
            "item": feedqueue.next_card(conn, skipped),
        }


@app.post("/api/queues/feeds/{proposal_id}")
def decide_feed(proposal_id: int, body: dict = Body(...)) -> dict:
    """Confirming repoints the show and pulls its episodes; rejecting only closes the card.

    The repoint itself goes through edits.apply() inside repair.apply(), so it lands in
    `edits` and decisions.jsonl and undoes like anything else. feed_proposals only records
    that the question was answered, so a rejected candidate is not offered again.
    """
    decision = body.get("decision")
    if decision not in ("confirmed", "rejected"):
        raise HTTPException(400, "decision must be 'confirmed' or 'rejected'")

    with db() as conn:
        row = conn.execute(
            "SELECT p.show_id, p.feed_url, p.home_url, s.slug, s.title FROM feed_proposals p "
            "JOIN shows s ON s.id = p.show_id WHERE p.id = ? AND p.resolved_at IS NULL",
            (proposal_id,)).fetchone()
        if not row:
            raise HTTPException(404, "no such proposal, or it is already decided")
        show_id, feed_url, home_url, slug, title = row

        applied = []
        if decision == "confirmed":
            try:
                feed = feeds.read(feed_url)
            except feeds.FeedError as e:
                # Do not close the card: the feed may simply be down, and marking it
                # rejected would mean never offering the right answer again.
                raise HTTPException(502, f"could not read the feed — {e}")
            outcome = repair.Outcome(slug, title, None, "repointed",
                                     "confirmed in the feed queue", feed_url, home_url,
                                     feed.title, feed.author, len(feed.episodes))
            applied = repair.apply(conn, show_id, outcome, feed)

        feedqueue.record(conn, proposal_id, decision)
        return {"applied": applied, "counts": feedqueue.counts(conn)}


@app.get("/api/queues/labels")
def label_queue(skip: str = "") -> dict:
    """One doubtful label, sampled lowest-agreement-first. No total on purpose."""
    skipped = [int(s) for s in skip.split(",") if s.strip().isdigit()]
    with db() as conn:
        return {
            "counts": labelqueue.counts(conn),
            "item": labelqueue.next_card(conn, skipped),
        }


@app.post("/api/queues/labels/{episode_id}")
def decide_label(episode_id: int, body: dict = Body(...)) -> dict:
    """Confirm keeps the primary and marks it human-verified; change replaces it. Both
    go through edits.label_episodes (audited, undoable) and append to
    docs/briefs/corrections.md -- the feedback half of the Phase 3 gate."""
    action = body.get("action")
    if action not in ("confirm", "change"):
        raise HTTPException(400, "action must be 'confirm' or 'change'")
    with db() as conn:
        try:
            got = labelqueue.decide(conn, episode_id, action,
                                    subject_slug=body.get("subject"))
        except ValueError as e:
            raise HTTPException(400, str(e))
        return {**got, "counts": labelqueue.counts(conn)}


@app.get("/api/apple-link/{episode_id}")
def apple_link(episode_id: int):
    """Redirect to the episode on Apple Podcasts -- the label queue's research link.
    Resolution degrades: episode page, else show page, else an Apple search."""
    with db() as conn:
        row = conn.execute(
            "SELECT s.title, s.feed_url, e.title, e.guid FROM episodes e "
            "JOIN shows s ON s.id = e.show_id WHERE e.id = ?",
            (episode_id,)).fetchone()
    if not row:
        raise HTTPException(404, "no such episode")
    try:
        url = apple.episode_url(*row)
    except Exception:
        # The lookup is a third-party nicety; its outage should degrade to a search,
        # never to a broken research flow.
        url = ("https://podcasts.apple.com/search?"
               + urllib.parse.urlencode({"term": row[0]}))
    return RedirectResponse(url, status_code=307)


@app.get("/api/vocabulary")
def vocabulary() -> dict:
    """The full live vocabulary, grouped by theme -- what the label queue's change sheet
    renders for search and browse. See vocab.tree()."""
    with db() as conn:
        return vocab.tree(conn)


@app.post("/api/edits/{edit_id}/undo")
def undo(edit_id: int) -> dict:
    with db() as conn:
        try:
            edits.undo(conn, edit_id)
        except edits.EditError as e:
            raise HTTPException(400, str(e))
        return {"counts": queues.inclusion_counts(conn)}


@app.get("/api/edits")
def recent_edits(limit: int = 20) -> dict:
    with db() as conn:
        return {"edits": edits.recent(conn, limit)}


@app.get("/api/health")
def health() -> dict:
    with db() as conn:
        return {
            "ok": True,
            "schema": migrations.current_version(conn),
            "shows": conn.execute(
                "SELECT count(*) FROM shows WHERE deleted_at IS NULL").fetchone()[0],
        }


# --- the built UI ----------------------------------------------------------------
# Mounted last so it never shadows /api. Absent in development, where Vite serves it.

if WEB_DIST.is_dir():
    app.mount("/assets", StaticFiles(directory=WEB_DIST / "assets"), name="assets")

    @app.get("/{full_path:path}")
    def spa(full_path: str) -> FileResponse:
        return FileResponse(WEB_DIST / "index.html")


def tailscale_ip() -> str:
    """hfab's tailnet address. Refuses to guess -- binding wide by accident is the one
    mistake this service must not make."""
    out = subprocess.run(["tailscale", "ip", "-4"], capture_output=True, text=True)
    ip = out.stdout.strip().splitlines()[0] if out.stdout.strip() else ""
    if not ip:
        raise SystemExit("tailscale is not up; refusing to bind to anything else")
    return ip


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host=tailscale_ip(), port=8828)

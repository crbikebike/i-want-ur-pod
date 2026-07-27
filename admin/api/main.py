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
from contextlib import contextmanager
from pathlib import Path

from fastapi import Body, FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from admin.api import edits, queues
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
        report = migrations.apply_all(conn)
        for line in report.lines():
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

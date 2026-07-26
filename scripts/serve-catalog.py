#!/usr/bin/env python3
"""Serve the catalog browser locally.

    python3 scripts/serve-catalog.py               # localhost only
    python3 scripts/serve-catalog.py --tailscale   # reachable from the tailnet

Binds localhost by DEFAULT on purpose: this machine shares a tailnet, and a browsing tool
should not become reachable by anyone else just because it was started. --tailscale is the
explicit opt-in.

Routes:
    GET  /                 the browser UI
    GET  /api/catalog      catalog-index.json (build it with build-catalog-index.py)
    GET  /api/verdicts     every verdict recorded so far
    POST /api/verdicts     record one verdict; writes through to disk immediately

Stdlib only -- no pip, per curation/arc-bakeoff/HFAB_PROMPT.md.
"""
import argparse
import json
import os
import posixpath
import shutil
import socket
import sys
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UI = ROOT / "tools" / "catalog-browser"
FONTS = ROOT / "design" / "kit" / "fonts"
INDEX = ROOT / "curation" / "arc-bakeoff" / "catalog-index.json"
# NOT verdicts-*.json -- that pattern is gitignored (.gitignore:41) and these are the
# valuable human output, meant to be committed.
VERDICTS = ROOT / "curation" / "arc-bakeoff" / "human-verdicts.json"

PORT = 8420  # 8000 / 8025 / 8080 are already taken on this box
VALID = {"right", "wrong", "unsure", "none", "clear"}

MIME = {".html": "text/html; charset=utf-8", ".css": "text/css; charset=utf-8",
        ".js": "text/javascript; charset=utf-8", ".json": "application/json; charset=utf-8",
        ".ttf": "font/ttf", ".woff2": "font/woff2", ".svg": "image/svg+xml",
        ".jpg": "image/jpeg", ".png": "image/png", ".ico": "image/x-icon"}


def load_verdicts():
    if VERDICTS.exists():
        try:
            return json.loads(VERDICTS.read_text())
        except json.JSONDecodeError:
            print(f"!! {VERDICTS.name} is corrupt; starting empty", file=sys.stderr)
    return {}


def save_verdicts(data):
    """Write via a temp file + replace so a crash mid-write cannot destroy the record."""
    tmp = VERDICTS.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=1, sort_keys=True) + "\n")
    tmp.replace(VERDICTS)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "catalog-browser"

    def log_message(self, fmt, *args):
        if "/api/" in (self.path or ""):
            print(f"  {self.command} {self.path}")

    # --- helpers ---------------------------------------------------------
    def _send(self, code, body=b"", ctype="application/json; charset=utf-8", extra=None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD" and body:
            self.wfile.write(body)

    def _json(self, code, obj):
        self._send(code, json.dumps(obj, ensure_ascii=False).encode("utf-8"))

    def _file(self, path: Path):
        if not path.is_file():
            return self._json(404, {"error": f"not found: {path.name}"})
        body = path.read_bytes()
        self._send(200, body, MIME.get(path.suffix.lower(), "application/octet-stream"))

    def _safe(self, base: Path, rel: str):
        """Resolve rel under base, refusing anything that escapes it."""
        target = (base / posixpath.normpath("/" + rel).lstrip("/")).resolve()
        try:
            target.relative_to(base.resolve())
        except ValueError:
            return None
        return target

    # --- routes ----------------------------------------------------------
    def do_GET(self):
        path = self.path.split("?", 1)[0]

        if path == "/api/catalog":
            if not INDEX.exists():
                return self._json(503, {"error": "catalog-index.json missing",
                                        "fix": "python3 curation/arc-bakeoff/build-catalog-index.py"})
            return self._file(INDEX)

        if path == "/api/verdicts":
            return self._json(200, load_verdicts())

        if path.startswith("/fonts/"):
            t = self._safe(FONTS, path[len("/fonts/"):])
            return self._file(t) if t else self._json(403, {"error": "forbidden"})

        rel = "index.html" if path == "/" else path.lstrip("/")
        t = self._safe(UI, rel)
        return self._file(t) if t else self._json(403, {"error": "forbidden"})

    do_HEAD = do_GET

    def do_POST(self):
        if self.path.split("?", 1)[0] != "/api/verdicts":
            return self._json(404, {"error": "no such endpoint"})
        try:
            n = int(self.headers.get("Content-Length") or 0)
            if n <= 0 or n > 64_000:
                raise ValueError("bad content length")
            payload = json.loads(self.rfile.read(n))
        except (ValueError, json.JSONDecodeError) as e:
            return self._json(400, {"error": f"bad request: {e}"})

        slug = payload.get("slug")
        verdict = payload.get("verdict")
        if not slug or verdict not in VALID:
            return self._json(400, {"error": f"slug required; verdict must be one of {sorted(VALID)}"})

        data = load_verdicts()
        rec = data.setdefault(slug, {"show": None, "arcs": {}})
        stamp = datetime.now(timezone.utc).isoformat(timespec="seconds")

        if payload.get("kind") == "arc":
            key = str(payload.get("index"))
            if verdict == "clear":
                rec["arcs"].pop(key, None)
            else:
                # name + count are stored as a checksum: if the detector changes and arc
                # indices shift, the exporter can tell that a verdict no longer lines up
                # rather than silently attaching it to a different arc.
                rec["arcs"][key] = {"v": verdict, "name": payload.get("name") or "",
                                    "count": payload.get("count") or 0, "at": stamp}
        else:
            rec["show"] = None if verdict == "clear" else {"v": verdict, "at": stamp}

        if not rec["arcs"] and not rec["show"]:
            data.pop(slug, None)
        save_verdicts(data)
        self._json(200, {"ok": True, "slug": slug, "verdicts": data.get(slug)})


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tailscale", action="store_true",
                    help="bind 0.0.0.0 so the tailnet can reach it (default: localhost only)")
    ap.add_argument("--port", type=int, default=PORT)
    args = ap.parse_args()

    if not INDEX.exists():
        print("catalog-index.json not built yet — run:\n"
              "   python3 curation/arc-bakeoff/build-catalog-index.py\n", file=sys.stderr)

    host = "0.0.0.0" if args.tailscale else "127.0.0.1"
    try:
        srv = ThreadingHTTPServer((host, args.port), Handler)
    except OSError as e:
        sys.exit(f"cannot bind {host}:{args.port} — {e}")

    print(f"catalog browser  http://localhost:{args.port}")
    if args.tailscale:
        ts = shutil.which("tailscale")
        ip = ""
        if ts:
            ip = os.popen("tailscale ip -4 2>/dev/null").read().strip().split("\n")[0]
        print(f"tailnet          http://{ip or socket.gethostname()}:{args.port}")
    print(f"verdicts         {VERDICTS}")
    print("ctrl-c to stop")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")


if __name__ == "__main__":
    main()

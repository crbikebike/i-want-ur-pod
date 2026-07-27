"""Re-read every show's feed and give the catalog back the text it was denied.

The 2026-07 import stored descriptions truncated at 299 characters, and the labelling run
that followed showed its model only the first **150** of those. Every subject in this
catalog was chosen from a sentence and a half. Meanwhile the feeds carry an average of
1,060 characters and the longest run to 3,499.

So this runs before anything in Phase 3 that costs money. Labelling on the truncated text
and re-fetching afterwards would mean paying for the whole pass twice.

    python -m admin.api.comb --dry-run
    python -m admin.api.comb

One HTTP request per show. A feed response contains every episode that show has ever
published, so ~288 requests covers all 28,773 episodes -- there is no per-episode fetch
and there is no API in the loop. Those requests go to publisher CDNs (megaphone, acast,
omny, simplecast), which serve every podcast app in existence and will not notice.

The Podcast Index dump is consulted first, as a **file**, to skip feeds already known
dead. That is the only thing it is used for here and it costs zero requests. Their API is
never called.
"""

from __future__ import annotations

import argparse
import sqlite3
import sys
from pathlib import Path

from admin.api import edits, feeds, runs
from admin.api import podcastindex as pi

ROOT = Path(__file__).resolve().parents[2]
DB = ROOT / "catalog/catalog.db"


def live_shows(conn: sqlite3.Connection) -> list[tuple]:
    """Every show worth reading. Cut shows are skipped -- they are not in the product, so
    spending a request and a description refresh on them buys nothing."""
    return conn.execute(
        """
        SELECT s.id, s.slug, s.title, s.feed_url,
               (SELECT count(*) FROM episodes e
                WHERE e.show_id = s.id AND e.deleted_at IS NULL) AS eps
        FROM shows s
        WHERE s.deleted_at IS NULL AND s.include_verdict IN ('keep', 'unreviewed')
        ORDER BY s.title
        """
    ).fetchall()


def dead_feeds(dump: str | Path | None) -> set[str]:
    """Feed URLs Podcast Index has already found dead.

    A hint, not a verdict. The dump is a snapshot rebuilt daily, so a feed it calls dead
    may have come back and one it calls alive may have just gone. It is used only to skip
    a request we would expect to fail, and a skipped show is reported rather than silently
    dropped -- those need a person, not a retry.
    """
    path = Path(dump) if dump else pi.DUMP
    if not path or not Path(path).exists():
        return set()
    conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    try:
        return {
            r[0] for r in conn.execute(
                "SELECT url FROM podcasts WHERE dead = 1 OR lastHttpStatus >= 400")
        }
    finally:
        conn.close()


def comb(conn: sqlite3.Connection, *, dump=None, dry_run: bool = False,
         limit: int | None = None, decisions_path: Path | None = None) -> runs.Run:
    shows = live_shows(conn)
    if limit:
        shows = shows[:limit]
    dead = dead_feeds(dump)

    run = runs.start(conn, "refetch", {"shows": len(shows), "dryRun": dry_run})
    print(f"combing {len(shows)} feeds"
          f"{' (dry run — nothing written)' if dry_run else ''}"
          f"{f'; {len(dead)} known-dead URLs loaded from the dump' if dead else ''}",
          flush=True)

    for show_id, slug, title, feed_url, eps in shows:
        if feed_url in dead:
            run.tally("skipped-dead")
            run.problem(f"{slug}: the dump marks this feed dead")
            print(f"  · {title[:38]:<40} skipped — dump says dead", flush=True)
            continue
        try:
            feed = feeds.read(feed_url, timeout=45)
        except feeds.FeedError as e:
            run.tally("unreadable")
            run.problem(f"{slug}: {str(e)[:90]}")
            print(f"  ✗ {title[:38]:<40} {str(e)[:60]}", flush=True)
            continue

        run.tally("read")
        if dry_run:
            longer = sum(
                1 for ep in feed.episodes
                for row in [conn.execute(
                    "SELECT length(coalesce(description,'')) FROM episodes "
                    "WHERE show_id=? AND guid=?", (show_id, ep.guid)).fetchone()]
                if row and len((ep.description or "").strip()) > row[0])
            run.tally("would-lengthen", longer)
            print(f"  · {title[:38]:<40} {len(feed.episodes):>4} in feed, "
                  f"{longer:>4} descriptions would grow", flush=True)
            continue

        got = edits.refresh_episodes(
            conn, show_id=show_id, episodes=feed.episodes, actor="agent:comb",
            note="feed re-read at full length", decisions_path=decisions_path)
        run.tally("descriptions", got["longer"])
        run.tally("durations", got["durations"])
        if got["longer"] or got["durations"]:
            print(f"  ✓ {title[:38]:<40} {got['longer']:>4} descriptions, "
                  f"{got['durations']:>4} durations", flush=True)

    runs.finish(conn, run)
    return run


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dry-run", action="store_true",
                    help="read the feeds and report what would change, writing nothing")
    ap.add_argument("--limit", type=int, help="only the first N shows, for a smoke test")
    ap.add_argument("--dump", help="path to the Podcast Index dump; defaults to "
                                   "$PODCASTINDEX_DUMP")
    args = ap.parse_args(argv)

    conn = sqlite3.connect(DB, timeout=30)
    conn.execute("PRAGMA foreign_keys = ON")
    run = comb(conn, dump=args.dump, dry_run=args.dry_run, limit=args.limit)
    print(f"\nrun {run.id}: {run.summary()}")
    for p in run.problems:
        print(f"  ! {p}")
    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())

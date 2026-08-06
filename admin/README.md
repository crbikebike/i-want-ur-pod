# The catalog workbench

A queue-driven tool for making the judgement calls the catalog is waiting on. Runs as a
service on hfab, reachable from anything on the tailnet.

    http://100.117.245.23:8828/

## Running it

It is a systemd user service and starts itself on boot.

    systemctl --user status workbench     # is it up
    systemctl --user restart workbench    # after changing the API
    journalctl --user -u workbench -f     # what it is doing

Working on the UI:

    cd admin/web && npm run dev           # vite on :5173, proxies /api to :8828
    cd admin/web && npm run build         # the service serves dist/

## Why it binds where it does

The service binds to hfab's Tailscale address, never `0.0.0.0`. There is no login
because reaching it at all *is* the authorisation. A wider bind would quietly turn that
from a reasonable posture into an open catalog editor, so the address is resolved from
`tailscale ip -4` at start time rather than hardcoded, and the service refuses to start
if Tailscale is down.

## The one write path

Every change goes through `edits.apply()`, which in a single transaction:

1. updates the row, so the screen is right immediately
2. appends to the `edits` table, giving an audit trail and undo
3. appends to `curation/source/decisions.jsonl`, which is tracked in git

All three or none. Two of three is worse than none because it looks like it worked.

`catalog.db` is deliberately *not* in git — 30 MB of binary that changes on every tap.
But the judgement calls inside it are the only irreplaceable thing in this project;
feeds can be refetched and models re-run. So the derived data stays out and the
decisions go in.

`test_only_one_write_path.py` scans every API module for SQL that writes a catalog table
and fails if it finds one.

## Nothing is ever deleted

`deleted_at` on every entity table. Soft deletion goes through the same write path as
any other edit, so it has the same undo. Every row here cost a feed fetch, a labelling
call, or a human deciding — reclaiming disk is not worth any of those.

## The database

`catalog/catalog.db`, WAL mode, durable. It is not rebuilt: `catalog/build/migrate.py`
imported it once and now refuses to overwrite it without `--force`. Schema changes are
numbered additive files in `catalog/migrations/`, applied at startup, and a migration
that tries to DROP or UPDATE is rejected.

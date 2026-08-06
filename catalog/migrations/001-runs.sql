-- Phase 3 and 4 put long-running jobs on this machine: labelling runs, the feed comber,
-- the publisher. They need somewhere to report and somewhere to be approved from, and
-- retrofitting that around a running service is worse than adding the table now.
--
-- Nothing writes to this yet. The workbench ships a Runs area that is honestly empty
-- until Phase 3 registers the first job kind.

CREATE TABLE runs (
  id          INTEGER PRIMARY KEY,
  -- 'relabel' | 'arcs' | 'entities' | 'comb' | 'publish' -- deliberately not a CHECK
  -- constraint, so a new job kind does not need a migration.
  kind        TEXT NOT NULL,
  status      TEXT NOT NULL DEFAULT 'pending'
              CHECK (status IN ('pending','running','done','failed','cancelled')),
  started_at  TEXT,
  finished_at TEXT,
  -- JSON. What the run was asked to do.
  args        TEXT,
  -- Human-readable outcome: "labelled 4,210 episodes, 312 escalated to 3 votes".
  summary     TEXT,
  log_path    TEXT,
  -- Runs that change arcs or vocabulary wait for a human; label runs auto-publish.
  approval    TEXT NOT NULL DEFAULT 'not-required'
              CHECK (approval IN ('not-required','pending','approved','rejected')),
  approved_at TEXT
);

CREATE INDEX runs_by_status ON runs (status, id DESC);
CREATE INDEX runs_by_kind   ON runs (kind, id DESC);

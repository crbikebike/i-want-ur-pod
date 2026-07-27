-- What each episode is about, with room for more than one run to have said so.
--
-- `episode_subjects` is keyed (episode_id, subject_id), so a second labelling run cannot
-- coexist with the first -- the two would collide on every episode they agreed about.
-- Changing a primary key means rebuilding the table, which the additive-only rule forbids
-- and which would destroy the only record of what the 2026-07 pass said. That record is
-- worth keeping: it is the thing the new run has to be measured against.
--
-- So a new table with run_id in the key, and the old run moves in as history. INSERT INTO
-- is additive; nothing is dropped and nothing is rewritten.
--
-- `agreement` is the column the last run left NULL on all 43,818 rows. The schema comment
-- on episode_subjects says outright: "Phase 3's relabel populates it." This is where.

CREATE TABLE IF NOT EXISTS episode_labels (
  episode_id INTEGER NOT NULL REFERENCES episodes(id),
  subject_id INTEGER NOT NULL REFERENCES subjects(id),
  -- In the key, so runs sit side by side and can be compared rather than replaced.
  run_id     TEXT    NOT NULL,
  role       TEXT    NOT NULL CHECK (role IN ('primary','secondary')),
  confidence TEXT    NOT NULL CHECK (confidence IN ('low','medium','high')),
  -- How many independent reads agreed. NULL when only one was taken -- which is honest,
  -- and different from 1, which would claim a vote happened and came out unanimous.
  agreement  INTEGER,
  votes      INTEGER,
  model      TEXT,
  at         TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (episode_id, subject_id, run_id)
);

CREATE INDEX IF NOT EXISTS episode_labels_by_subject ON episode_labels (subject_id, run_id);
CREATE INDEX IF NOT EXISTS episode_labels_by_run     ON episode_labels (run_id, confidence);

-- The 2026-07 Haiku pass, preserved. Its agreement stays NULL because none was taken.
INSERT INTO episode_labels (episode_id, subject_id, run_id, role, confidence,
                            agreement, votes, model)
SELECT episode_id, subject_id, coalesce(run_id, '2026-07-theming'), role, confidence,
       agreement, NULL, model
FROM episode_subjects;

-- Real-world things an episode is about: a case, a company, a person, a place, an era, a
-- work. The `entities` table has been empty since Phase 1 with a comment saying
-- "Populated in Phase 3".
--
-- These stay out of `edges` for the same reason episode-to-theme edges were dropped in
-- Phase 1: at two or three per episode that is 70k rows and roughly 8 MB, and nothing
-- traverses them. Only aggregated show-to-entity edges get promoted, which is what
-- "explain the connection" actually reads and is small.
CREATE TABLE IF NOT EXISTS episode_entities (
  episode_id INTEGER NOT NULL REFERENCES episodes(id),
  entity_id  INTEGER NOT NULL REFERENCES entities(id),
  run_id     TEXT    NOT NULL,
  confidence TEXT    NOT NULL CHECK (confidence IN ('low','medium','high')),
  at         TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (episode_id, entity_id, run_id)
);

CREATE INDEX IF NOT EXISTS episode_entities_by_entity ON episode_entities (entity_id);

-- Subjects a run wanted and could not use, waiting on a human. The browsable vocabulary
-- stays a finite menu -- 148 is already a lot to navigate -- so a run proposes and never
-- self-serves. Workbench-owned, like feed_proposals.
CREATE TABLE IF NOT EXISTS subject_proposals (
  id          INTEGER PRIMARY KEY,
  name        TEXT NOT NULL,
  definition  TEXT,
  run_id      TEXT NOT NULL,
  -- What the run would have labelled with it, as evidence. A proposal with no examples is
  -- an opinion; with five episode titles it is an argument.
  examples    TEXT,
  seen        INTEGER NOT NULL DEFAULT 1,
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  resolved_at TEXT,
  resolved_as TEXT CHECK (resolved_as IN ('accepted','merged','rejected')),
  merged_into INTEGER REFERENCES subjects(id),
  UNIQUE (name, run_id)
);

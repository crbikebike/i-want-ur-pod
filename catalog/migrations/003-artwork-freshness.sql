-- Knowing when a show's artwork last changed, so clients can be told to fetch it again.
--
-- Apple serves covers with `cache-control: max-age=16480651` -- 190 days. A phone that
-- loads a cover today keeps it until next year. Re-scanning feeds cannot touch that:
-- once a client holds a copy, only a different URL will dislodge it.
--
-- So the API appends ?v=<artwork_updated_at> to the derived thumbnail. Same image while
-- nothing changes, and a URL every cache treats as new the moment it does.
--
-- The comber (Phase 4) sets these. Until then they are NULL and no version param is
-- added, which is correct: we have no evidence the art has ever changed.

ALTER TABLE shows ADD COLUMN artwork_updated_at TEXT;

-- When the comber last looked, whether or not anything changed. Lets it prioritise the
-- shows it has not checked in longest rather than re-walking all 315 every pass.
ALTER TABLE shows ADD COLUMN artwork_checked_at TEXT;

CREATE INDEX shows_artwork_staleness
  ON shows (artwork_checked_at) WHERE deleted_at IS NULL;

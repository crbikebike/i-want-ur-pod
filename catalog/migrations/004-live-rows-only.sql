-- The one-show-per-feed index was counting the dead.
--
-- shows_one_reviewed_per_feed enforced "at most one reviewed show per feed", which is
-- right, but it had no opinion about deleted_at. Merging a duplicate away leaves its row
-- in place -- soft delete is the rule here -- so the corpse kept occupying the feed's
-- one slot and unflagging the survivor collided with it.
--
-- Dropping an index destroys no data, which is why the additive-only check allows it.

DROP INDEX shows_one_reviewed_per_feed;

CREATE UNIQUE INDEX shows_one_reviewed_per_feed
  ON shows (feed_url)
  WHERE include_verdict <> 'suspect' AND deleted_at IS NULL;

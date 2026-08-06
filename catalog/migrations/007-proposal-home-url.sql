-- The Apple page for a proposed feed, so the feed card can offer the same slide-up player
-- the inclusion card has.
--
-- Stored rather than looked up when the card renders. The lookup keys on the feed URL in
-- Podcast Index's dump, which has no index on that column, so every card would cost a scan
-- of 4.7M rows. It is also wrong in principle: the workbench must run whether or not a
-- 4 GB file happens to be sitting next to it, and a card that silently loses its player
-- when the dump is absent is the same regression this fixes.

ALTER TABLE feed_proposals ADD COLUMN home_url TEXT;

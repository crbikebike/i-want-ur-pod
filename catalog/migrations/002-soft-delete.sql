-- Soft delete, as a rule for the whole database.
--
-- Nothing in this catalog is ever removed. Every row here cost something to produce --
-- a feed fetch, a labelling call, or a human deciding. Deleting one to save disk trades
-- something irreplaceable for something free.
--
-- deleted_at is NULL for live rows and an ISO timestamp for gone ones. Reads filter it;
-- the workbench can always put a row back; and a mistake costs a tap rather than a
-- re-import.
--
-- This also defuses the merge action. Folding "Slow Burn: Biggie & Tupac" into Slow Burn
-- used to mean destroying a show row, which needed confirmations and extra tests. Now it
-- marks the child deleted and moves its episodes, and is as reversible as anything else.

ALTER TABLE shows      ADD COLUMN deleted_at TEXT;
ALTER TABLE episodes   ADD COLUMN deleted_at TEXT;
ALTER TABLE arcs       ADD COLUMN deleted_at TEXT;
ALTER TABLE themes     ADD COLUMN deleted_at TEXT;
ALTER TABLE subjects   ADD COLUMN deleted_at TEXT;
ALTER TABLE entities   ADD COLUMN deleted_at TEXT;
ALTER TABLE people     ADD COLUMN deleted_at TEXT;
ALTER TABLE networks   ADD COLUMN deleted_at TEXT;

-- Partial indexes: the common query is "the live ones", and these keep that cheap
-- without carrying the deleted rows around in the index.
CREATE INDEX shows_live    ON shows (id)    WHERE deleted_at IS NULL;
CREATE INDEX episodes_live ON episodes (show_id, published_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX arcs_live     ON arcs (show_id) WHERE deleted_at IS NULL;

-- Why the maintenance agent wants a row gone: 'dead-feed', 'gone-from-feed',
-- 'merged-into-parent', 'cut-by-human'. Free text, because Phase 4 will invent reasons
-- this migration cannot predict.
ALTER TABLE shows    ADD COLUMN deleted_reason TEXT;
ALTER TABLE episodes ADD COLUMN deleted_reason TEXT;
ALTER TABLE arcs     ADD COLUMN deleted_reason TEXT;

# Podcast episode + story-arc data (reusable)

Real episodes and **derived story arcs** for the design-kit Podcast Detail screen,
so mockups use real data instead of invented fixtures.

- **`<slug>.json`** — one file per show: `show` (title, author, category, summary,
  feedUrl), `episodes[]` (arc, episodeTitle, part, season, episodeNumber, date,
  durationSec, episodeType, summary), `arcs[]` (name, season, parts,
  episodeIndices), and `counts`. Slug matches the cover in `../art/<slug>.jpg`.

## Where seasons & arcs come from

The Apple **search list** is show-level only (title/author/artwork/feed URL) — it
carries **no episodes or seasons**. Episode data comes from the show's **RSS feed**:

- **Season / episode numbers**: `<itunes:season>` / `<itunes:episode>` — *optional*.
  American History Tellers sets them; The Explorers Podcast does not.
- **Story arcs**: derived from the episode-title structure by
  `scripts/fetch-podcast-episodes.py`:
  - `Arc | Episode Title | N`  → arc, title, part  (art19 / AHT)
  - `Arc - Part N - Subtitle`  → arc, subtitle, part  (Explorers)
  - anything else → a "single" (no arc)

When a feed has neither seasons nor arcs, the detail screen degrades gracefully
(no season badge / no arc grouping — just date · duration).

## Regenerate / add a show

```bash
python3 scripts/fetch-podcast-episodes.py     # refresh *.json from the feeds
python3 design/kit/build-detail.py            # regenerate podcast-detail-<slug>.html
```

Add a `slug: feed_url` line to `FEEDS` in `scripts/fetch-podcast-episodes.py`
(and the matching `slug` to `scripts/fetch-podcast-art.py`'s ROSTER for the cover),
then re-run both. Source of truth is the live feed; these files are a cache used for
internal design mockups.

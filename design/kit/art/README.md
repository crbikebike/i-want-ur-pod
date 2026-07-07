# Podcast cover art + metadata (reusable)

Real podcast covers and directory metadata for the design-kit prototypes, so
prototypes don't re-pull the same data.

- **`<slug>.jpg`** — 300×300 cover art. Screens reference it as `../art/<slug>.jpg`
  (that path resolves both when a screen is opened directly and inside the
  `prototype.html` `srcdoc`).
- **`podcasts.json`** — one entry per slug: `title`, `author`, `feedUrl`,
  `homeUrl`, `artworkUrl` (Apple's 600×600 original), `genre`,
  `itunesCollectionId`, `file`. Use this for real names/authors/feeds in new
  mockups — no need to hit the network again.

## Regenerate / add a show

Covers come from Apple's iTunes Search API (the same source the app uses).

```bash
python3 scripts/fetch-podcast-art.py          # add missing art + refresh manifest
python3 scripts/fetch-podcast-art.py --force  # re-download every image
```

Add a `slug: "search term"` line to `ROSTER` in `scripts/fetch-podcast-art.py`
and re-run. **Keep slugs stable** — screens reference them by name.

Source of truth is the API; these files are a cache. Art is Apple-hosted and
used here only for internal design mockups.

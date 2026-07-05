# Curated "Start Here" List — Schema & Curation

**Single source of truth for Epic E1-S2 (curated shelf).** The story-driven
first-run shelf is a **hand-curated JSON file bundled in the app** — no backend, no
network, works offline. This doc defines its shape, where it lives, and how to
curate it.

---

## Why bundled JSON

The product's pitch is editorial: *story-driven and investigative podcasts, less
talk show, more story arcs.* That voice can't come from a "top charts" query — it's
a human pick. Bundling the list keeps us local-first (a key project decision) and
means the shelf renders instantly and offline on first launch.

The trade-off is honest: **the list is only as fresh as the last app release**, and
curating it is a recurring editorial chore. That's acceptable for the opener.

---

## Location

- **Shipped file:** `IWantUrPod/Resources/curated-start-here.json` (bundle resource).
- **Loader:** decodes at launch into the same value type the shelf renders. The keys
  below are a **superset of `SearchResult`** (`Packages/DirectoryKit/.../SearchResult.swift`)
  so a curated entry and a search result can share a row view. The only addition is
  the editorial `blurb`.

---

## Schema

A JSON **array** of entries. Each entry:

| Key | Type | Required | Notes |
|---|---|---|---|
| `title` | string | yes | Show title as displayed. |
| `author` | string | yes | Publisher / studio (matches `Podcast.author`). |
| `feedUrl` | string (URL) | yes | RSS feed URL — the subscribe handle and identity. Must be a real, reachable feed. |
| `homeUrl` | string (URL) | no | Show home page. |
| `artworkUrl` | string (URL) | no | High-res square artwork (≥1400px preferred). |
| `category` | string | no | e.g. `True Crime`, `Documentary`, `History`. |
| `blurb` | string | no | One editorial sentence on *why this is a good place to start*. This is the curated voice. |

Key names (`feedUrl`, `homeUrl`, `artworkUrl`) match the existing
`fixtures/sample-podcasts.json` and `SearchResult` `CodingKeys` **exactly** — do not
rename to camelCase URL.

### Example (`curated-start-here.json`)

```json
[
  {
    "title": "Bone Valley",
    "author": "Lava for Good Podcasts",
    "feedUrl": "https://www.omnycontent.com/d/playlist/e73c998e-6e60-432f-8610-ae210140c5b1/2b18f6f0-09c0-471e-b663-aeed010410fa/da6eda02-def2-4de4-a1c2-aeed010456a1/podcast.rss",
    "homeUrl": "https://lavaforgood.com/",
    "artworkUrl": "https://is1-ssl.mzstatic.com/image/thumb/Podcasts211/v4/aa/72/2f/aa722ff2-7e96-dfbd-fd98-d23d36d035b3/mza_9383434172737455327.jpg/3000x3000bb.png",
    "category": "True Crime",
    "blurb": "A nine-part investigation into a wrongful murder conviction — start at episode one; it's built as a single arc."
  },
  {
    "title": "Adrift",
    "author": "Apple TV / Blanchard House",
    "feedUrl": "https://rss.art19.com/adrift",
    "homeUrl": "https://apple.co/Adrift",
    "artworkUrl": "https://is1-ssl.mzstatic.com/image/thumb/Podcasts221/v4/4d/fa/ca/4dfaca28-d1af-75a9-e1a3-80758095ff9e/mza_6587373527288087178.jpeg/3000x3000bb.png",
    "category": "Documentary",
    "blurb": "A single true story told across the season — the kind of arc this app is built for."
  }
]
```

`fixtures/sample-podcasts.json` is a ready pool of correctly-shaped entries to draw
from (add a `blurb` per pick).

---

## Curation guide

1. **Pick for arc, not cadence.** Favor shows built as a story (limited series,
   investigations, narrative documentary) over open-ended talk/interview shows.
2. **One `blurb` per entry**, one sentence, answering *"why start here?"* — that's the
   editorial value the shelf adds over raw search.
3. **Verify the `feedUrl` is live** before committing (fetch it once; it must parse per
   `feed-field-mapping.md`).
4. **Keep it short.** A curated shelf is a handful of confident picks, not a directory.
5. Prefer artwork ≥1400px square.

---

## Loader behavior (determinate)

- The shelf renders **every valid entry** in file order.
- A **malformed entry** (missing a required key, unparseable URL) is **skipped, not
  fatal** — the rest of the shelf still renders.
- A missing/empty file yields an **empty shelf**, not a crash (E1 still shows the
  first-run explainer and search).
- Tapping an entry routes to the **adaptive podcast detail (E2)**, keyed by `feedUrl`.

These map 1:1 to E1-S2's determinate tests in `ROADMAP.md`.

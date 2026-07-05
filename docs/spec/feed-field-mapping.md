# Feed → Model Field Mapping

**Single source of truth for Epic E0 (Feed Parsing).** When `FeedParsingKit`
turns a feed URL into a `Podcast` + `[Episode]`, this table defines exactly which
feed element populates which model field, and what to do when it is missing. If a
mapping question isn't answered here, answer it here first, then implement.

Model types live in `Packages/PodcastModels/Sources/PodcastModels/` — treat those
`@Model` definitions as authoritative for names and types.

---

## Scope

- Input: an RSS 2.0 feed (the podcast norm), commonly carrying the
  `itunes:` (Apple) and `podcast:` (Podcasting 2.0) namespaces.
- Output: one `Podcast` and its `[Episode]`. Chapters are **out of scope for E0**
  (they land with `ChapterKit`); leave `Episode.chapters` empty.
- The natural identity keys are `Podcast.feedURL` and `Episode.guid`. Parsing the
  same feed twice must produce the same identities (idempotent upsert).

---

## Podcast (channel-level)

| Model field | Feed source (in priority order) | Missing → |
|---|---|---|
| `feedURL` | the URL that was fetched (canonical identity) | n/a — required input |
| `title` | `<channel><title>` | required; if absent, treat feed as invalid (typed error) |
| `author` | `<channel><itunes:author>` → `<channel><managingEditor>` → `<channel><itunes:owner><itunes:name>` | `""` |
| `homeURL` | `<channel><link>` | `nil` |
| `artworkURL` | `<channel><itunes:image href>` → `<channel><image><url>` | `nil` |
| `category` | first `<channel><itunes:category text>` → `<channel><category>` | `""` |
| `summary` | `<channel><description>` → `<channel><itunes:summary>` | `""` |
| `isSubscribed` | **never set from the feed** — owned by the subscribe flow (E2) | preserve existing value on re-parse |
| `dateAdded` | **never set from the feed** — set once when first stored | preserve on re-parse |

**"Hosts / channel / studio" note:** RSS has no structured host list. `author`
(publisher/studio) is the only reliably present identity field, so it is what the
detail screen shows. Do not invent a hosts field. Structured hosts (`podcast:person`)
are parked with the Podcasting 2.0 work.

---

## Episode (item-level)

One `Episode` per `<item>`. **Skip (do not fail) any `<item>` with no usable audio
enclosure** — an episode with nothing to play is not an episode.

| Model field | Feed source (in priority order) | Missing → |
|---|---|---|
| `guid` | `<item><guid>` → `<item><enclosure url>` | if both absent, **skip the item** |
| `title` | `<item><title>` → `<item><itunes:title>` | `"Untitled Episode"` |
| `summary` | `<item><description>` → `<item><itunes:summary>` → `<item><content:encoded>` | `""` |
| `publishDate` | `<item><pubDate>` (RFC 822) | `Date.distantPast` (sorts last in newest-first) |
| `duration` (seconds) | `<item><itunes:duration>` — accepts `SS`, `MM:SS`, `HH:MM:SS`, or plain seconds | `0` (model already treats `0` as "unknown") |
| `audioURL` | `<item><enclosure url>` where `type` is audio/* | if absent, **skip the item** |
| `remoteArtworkURL` | `<item><itunes:image href>` | `nil` (UI falls back to `Podcast.artworkURL`) |
| `isExplicit` | `<item><itunes:explicit>` == `yes`/`true` | `false` |
| `downloadState` | **never from the feed** — `.notDownloaded`; owned by `DownloadKit` (E4) | preserve on re-parse |
| `playbackProgress` | **never from the feed** — owned by `PlaybackKit` (E4) | preserve on re-parse |

**Re-parse / upsert rule:** match on identity (`Podcast.feedURL`, `Episode.guid`).
Update feed-derived fields; **never clobber** the user-owned fields marked "never
from the feed" (`isSubscribed`, `dateAdded`, `downloadState`, `playbackProgress`).

---

## Ordering & parsing behavior

- **Episode order:** the UI sorts newest-first by `publishDate`; the parser need not
  pre-sort but must populate `publishDate` per the rule above.
- **Streaming decode:** feeds can be large; decode incrementally (e.g. `XMLParser`)
  rather than loading a full DOM.
- **HTML in `summary`:** keep the raw feed string; the detail screen decides how to
  render/strip. Do not lossily pre-strip in the parser.

## Error model (determinate)

`FeedParsingKit` surfaces **typed errors, never traps**:

| Situation | Result |
|---|---|
| HTTP non-2xx / network failure | `throw` a typed fetch error carrying the status |
| Body isn't XML / no `<rss>`/`<channel>` | `throw` a typed malformed-feed error |
| `<channel>` present but `<title>` missing | `throw` malformed-feed error |
| Individual `<item>` missing guid **and** enclosure | **skip that item**, continue |
| Zero valid items after skips | succeed with an empty `episodes` array (valid empty show) |

These map 1:1 to E0-S1's determinate tests in `ROADMAP.md`.

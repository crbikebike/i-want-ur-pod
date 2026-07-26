"""Pure helpers for the catalog build. No I/O, no database, no globals.

These are separated out because they are the functions where a quiet bug is most
expensive. `normalize_feed_url` in particular is the join key between catalog.json
(which has no slug, only an integer id and a feedUrl) and every other source file --
so a normalization mistake silently drops a show instead of raising.
"""

from __future__ import annotations

import math
import re
import unicodedata
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

# Query parameters that identify a referrer rather than the resource. Stripped so two
# records of the same feed match. Anything not listed here is kept -- plenty of feeds
# carry a required id or auth token and dropping it would break the feed.
_TRACKING_PARAM_PREFIXES = ("utm_",)
_TRACKING_PARAMS = frozenset(
    {
        "fbclid",
        "gclid",
        "mc_cid",
        "mc_eid",
        "ref",
        "refid",
        "at_medium",
        "at_campaign",
    }
)


def normalize_feed_url(url: str | None) -> str:
    """Canonicalize a feed URL for comparison.

    Folds the host to lowercase, drops trailing slashes, removes referrer-tracking
    params, and sorts what remains. Deliberately does NOT touch the scheme or the path
    case: http and https are different endpoints, and podcast hosts serve
    case-sensitive paths.
    """
    if url is None or not url.strip():
        raise ValueError("feed URL is empty")

    parts = urlsplit(url.strip())

    host = parts.netloc.lower()

    path = parts.path
    # "https://example.com/" has no path to strip -- keep the root slash so the URL
    # stays well-formed.
    if path not in ("", "/"):
        path = path.rstrip("/")

    kept = [
        (k, v)
        for k, v in parse_qsl(parts.query, keep_blank_values=True)
        if k.lower() not in _TRACKING_PARAMS
        and not k.lower().startswith(_TRACKING_PARAM_PREFIXES)
    ]
    query = urlencode(sorted(kept))

    # Fragments never identify a feed.
    return urlunsplit((parts.scheme, host, path, query, ""))


def slugify(text: str | None) -> str:
    """Derive a stable slug from a title.

    Matches the conventions already present in curation/source/ -- "99% Invisible"
    becomes "99-invisible" and "Alice Isn't Dead" becomes "alice-isn-t-dead" -- because
    those slugs are already the identity of 303 files and must not shift.
    """
    if text is None:
        raise ValueError("cannot slugify None")

    # Strip accents so "Épisode" and "Episode" produce the same slug.
    decomposed = unicodedata.normalize("NFKD", text)
    ascii_only = "".join(c for c in decomposed if not unicodedata.combining(c))

    slug = re.sub(r"[^a-z0-9]+", "-", ascii_only.lower()).strip("-")
    if not slug:
        raise ValueError(f"title has no sluggable characters: {text!r}")
    return slug


def split_display(display: str) -> tuple[str | None, str]:
    """Split an episode title into its segment prefix and the rest.

    The 2026-07 regex cascade already recorded this on existing episodes, so the build
    prefers the stored values. This exists for episodes that arrive later, during a
    live-feed reconcile, where nothing has run over them yet.

    "American Revolution | Saratoga | 4" -> ("American Revolution", "Saratoga | 4")
    """
    if "|" not in display:
        return None, display.strip()

    prefix, rest = display.split("|", 1)
    prefix, rest = prefix.strip(), rest.strip()
    if not prefix:
        return None, rest
    return prefix, rest


def jaccard(a: set, b: set) -> float:
    """Overlap of two sets, 0.0 when either is empty.

    The empty case matters: two shows with no themes share nothing, so 0/0 must not
    come out as perfect similarity.
    """
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)


def cosine(a: dict, b: dict) -> float:
    """Cosine similarity over sparse weight vectors, 0.0 when either is empty.

    Magnitude-insensitive on purpose: a 700-episode show and a 6-part series with the
    same thematic mix should read as similar rather than the big one dominating.
    """
    if not a or not b:
        return 0.0

    shared = a.keys() & b.keys()
    if not shared:
        return 0.0

    dot = sum(a[k] * b[k] for k in shared)
    norm_a = math.sqrt(sum(v * v for v in a.values()))
    norm_b = math.sqrt(sum(v * v for v in b.values()))
    if norm_a == 0 or norm_b == 0:
        return 0.0
    return dot / (norm_a * norm_b)

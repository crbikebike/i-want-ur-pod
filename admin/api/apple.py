"""Resolve an episode to its Apple Podcasts page, for the label queue's research link.

Reviewing a doubtful label usually means listening to a minute of the episode, and the
reviewer's player is Apple Podcasts. The catalog stores no Apple ids -- follows the
pattern of scripts/fetch-podcast-art.py, which resolves shows against the iTunes Search
API at need rather than persisting a third-party's identifiers.

Resolution: search the show by title and pick the result whose feedUrl matches ours
(exact first, then host+path -- feeds move between http/https and trailing slashes);
then look up the show's episodes and match ours by guid, falling back to exact title.
Every miss degrades gracefully: no episode match links the show page, no show match
links an Apple search for the show. A research link that lands *near* the episode still
beats a copy-paste into a search box.

Lookups are cached per process. This is the workbench, one person's tool -- a dict is
the right amount of infrastructure.
"""

from __future__ import annotations

import json
import urllib.parse
import urllib.request

SEARCH = "https://itunes.apple.com/search"
LOOKUP = "https://itunes.apple.com/lookup"

_collection: dict[str, int | None] = {}   # feed_url -> collectionId
_episodes: dict[int, list[dict]] = {}     # collectionId -> episode entries


def _get(url: str) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": "i-want-ur-pod workbench"})
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read().decode("utf-8"))


def _norm(feed: str | None) -> str:
    """host+path, lowercased, no scheme, no trailing slash: the parts of a feed URL
    publishers do not churn."""
    if not feed:
        return ""
    p = urllib.parse.urlparse(feed.strip())
    return (p.netloc.lower() + p.path.rstrip("/")).removeprefix("www.")


def collection_id(show_title: str, feed_url: str | None) -> int | None:
    key = feed_url or show_title
    if key in _collection:
        return _collection[key]
    query = urllib.parse.urlencode(
        {"media": "podcast", "limit": 25, "term": show_title})
    results = _get(f"{SEARCH}?{query}").get("results") or []
    ours = _norm(feed_url)
    match = next((r for r in results if ours and _norm(r.get("feedUrl")) == ours), None)
    if match is None:
        # No feed agreement: only trust an exact title, otherwise admit defeat --
        # a wrong show would send the reviewer to research the wrong episode.
        match = next((r for r in results
                      if (r.get("collectionName") or "").strip().lower()
                      == show_title.strip().lower()), None)
    _collection[key] = match.get("collectionId") if match else None
    return _collection[key]


def episode_url(show_title: str, feed_url: str | None,
                episode_title: str, guid: str | None) -> str:
    cid = collection_id(show_title, feed_url)
    if cid is None:
        query = urllib.parse.urlencode({"term": show_title})
        return f"https://podcasts.apple.com/search?{query}"

    if cid not in _episodes:
        query = urllib.parse.urlencode(
            {"id": cid, "entity": "podcastEpisode", "limit": 300})
        _episodes[cid] = (_get(f"{LOOKUP}?{query}").get("results") or [])[1:]

    found = pick_episode(_episodes[cid], episode_title, guid)
    if found and found.get("trackViewUrl"):
        return found["trackViewUrl"]
    return f"https://podcasts.apple.com/podcast/id{cid}"


def pick_episode(entries: list[dict], title: str, guid: str | None) -> dict | None:
    """Guid is identity when Apple carries it; title equality is the fallback. Pure,
    so the matching is testable without the network."""
    if guid:
        for e in entries:
            if e.get("episodeGuid") == guid:
                return e
    want = title.strip().lower()
    for e in entries:
        if (e.get("trackName") or "").strip().lower() == want:
            return e
    return None

"""Shows whose feed serves a different programme than the catalogue row claims.

Lives here rather than in the importer so both can read it: the importer sets the flag,
and the workbench explains it. Detection cannot find these -- there is no duplicate to
notice and no overlap to measure, because the row simply describes something the feed
does not contain. Each one was caught by reading episode titles.
"""

EXPLICIT_SUSPECTS = {
    # Catalogued as a limited series, but the feed returns 722 episodes of an ongoing
    # numbered true-crime show ("692 // The Mysterious Death of Christian Pilnacek").
    "Fake Diana: Case of the Missing Blue Diamond":
        "the feed returns an unrelated ongoing true-crime show, not this series",

    # Not Serial. The feed is an RSS-parser test fixture on an S3 bucket, with episodes
    # named after parser edge cases. All seven were theme-labelled anyway.
    "Serial (Season 1)":
        "the feed is an RSS-parser test fixture, not a podcast",

    # Catalogued as Goalhanger's history series with Dalrymple and Anand;
    # feeds.megaphone.fm/empire serves the crypto show of the same name. 657 episodes of
    # finance news were labelled as narrative history.
    "Empire":
        "the feed serves a different show with the same name — crypto, not history",
}

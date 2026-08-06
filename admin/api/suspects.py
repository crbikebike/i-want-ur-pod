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


# Rows whose feed serves a different podcast, found by sweeping the catalogue for shows
# whose two publisher fields share no distinctive word -- `network` is the curator's note
# about the show they meant, `author` was copied from whatever the import matched -- and
# then reading every candidate's episode titles by hand.
#
# The verdicts on these were made against the wrong podcast. Nineteen were cut and eight
# kept on evidence that described something else entirely, which is why repairing the feed
# also returns the verdict to unreviewed.
#
# Not a detector. Each line is a judgement someone made by looking, and the note is what
# they saw.
WRONG_FEED = {
    "Anatomy of Doubt":        "a generic true-crime show at EP196, not the TAL/ProPublica series",
    "Animal":                  "a National Park Service feed, not the NYT's Sam Anderson series",
    "Broken Record":           "a high school radio station — 'concerts with mom'",
    "Earshot":                 "WXXI Rochester local news, not ABC RN's Earshot",
    "Fake Diana: Case of the Missing Blue Diamond":
                               "an ongoing numbered true-crime show from Crawlspace Media",
    "Fallout":                 "a Fallout video-game fan podcast, not the Essendon doping series",
    "Fool Me Once":            "self-help communication tips, not ABC's Unravel season 3",
    "Gangster Capitalism":     "a lone 'Opinion Trailer' under a different author",
    "Hollywoodland":           "a Portuguese-language film review show",
    "Homecoming":              "Dr. Thema's wellness interviews, not the Gimlet drama",
    "Love + Radio":            "'2 worst Jobs n the world' — not Nick van der Kolk",
    "Proxy":                   "a Norwegian-language school programme",
    "Rivals":                  "live football reaction, not The Ringer's documentary anthology",
    "Sirens":                  "two episodes, neither the BBC Yorkshire Ripper series",
    "StartUp":                 "Y Combinator's advice show, not Gimlet's",
    "The Cipher":              "a single episode called 'Welcome to Restart'",
    "The Detectives":          "'F Hole', 'American Cheese' — comedy, not the CBC series",
    "The Fifth Estate":        "'Torch Of Liberty Media Foundation', not CBC",
    "The Gun Machine":         "a motivational show; the import recorded the author as 건박",
    "The Sellout":             "'Sleepy Time Philosophy', not Neon Hum's series",
    "The Shift":               "manifesting masterclasses, not Bloomberg",
    "The Turnaround":          "'Business Leader' EP1-5, not Jesse Thorn's interview show",
    "This Land":               "'This Land That I Love' — 'Cults VS Religions'",
    "Undisclosed":             "one episode titled 'UNDISCLOSED' under an unrelated author",
}

# Repointed by hand before this list existed, and left empty because nothing had fetched
# the corrected feed yet. Same repair, without the search.
NEEDS_EPISODES = {
    "Empire: World History", "The Clearing", "STORIES by Lea Thau",
    "Theory of Everything", "Uncover", "Cautionary Tales", "Hit Parade",
}

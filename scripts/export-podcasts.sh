#!/usr/bin/env bash
#
# Export the local Apple Podcasts subscription library to JSON + OPML.
#
# RUN THIS ON YOUR MAC. The Podcasts SQLite DB lives in your macOS user
# Library — it is not present on the Linux dev box.
#
# Usage:
#   scripts/export-podcasts.sh [output-dir]      # default: ./fixtures
#
set -euo pipefail

DB=$(ls "${HOME}/Library/Group Containers/"*.groups.com.apple.podcasts/Documents/MTLibrary.sqlite 2>/dev/null | head -1 || true)
if [[ -z "${DB}" || ! -f "${DB}" ]]; then
  echo "error: Apple Podcasts library (MTLibrary.sqlite) not found." >&2
  echo "       Open the Podcasts app once so it creates/syncs the DB, then retry." >&2
  exit 1
fi

OUTDIR="${1:-$(pwd)/fixtures}"
mkdir -p "$OUTDIR"
JSON="${OUTDIR}/podcasts.json"          # FULL personal list — gitignored, stays local
OPML="${OUTDIR}/podcasts.opml"          # FULL personal list — gitignored, stays local
SAMPLE="${OUTDIR}/sample-podcasts.json" # sanitized PUBLIC sample — safe to commit

# Optional columns vary by Podcasts version — include them only if present.
has() { sqlite3 "$DB" "PRAGMA table_info(ZMTPODCAST);" | cut -d'|' -f2 | grep -qx "$1"; }
AUTHOR=$(has ZAUTHOR   && echo ZAUTHOR   || echo "NULL")
IMAGE=$( has ZIMAGEURL && echo ZIMAGEURL || echo "NULL")
CATEGORY=$(has ZCATEGORY && echo ZCATEGORY || echo "NULL")

# --- JSON fixture (sqlite3 handles all escaping) ---
sqlite3 -json "$DB" "
  SELECT ZTITLE       AS title,
         ${AUTHOR}    AS author,
         ZFEEDURL     AS feedUrl,
         ZWEBPAGEURL  AS homeUrl,
         ${IMAGE}     AS artworkUrl,
         ${CATEGORY}  AS category
  FROM ZMTPODCAST
  WHERE ZFEEDURL IS NOT NULL
  ORDER BY ZTITLE COLLATE NOCASE;
" > "$JSON"

# --- OPML (standard subscription interchange) ---
# Use an unlikely field separator so titles containing '|' don't break parsing.
US=$'\x1f'
esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'; }
{
  echo '<?xml version="1.0" encoding="utf-8"?>'
  echo '<opml version="1.0"><head><title>Podcast subscriptions</title></head><body>'
  sqlite3 -separator "$US" "$DB" \
    "SELECT ZTITLE, ZFEEDURL, COALESCE(ZWEBPAGEURL,'') FROM ZMTPODCAST WHERE ZFEEDURL IS NOT NULL ORDER BY ZTITLE COLLATE NOCASE;" \
    | while IFS="$US" read -r title feed home; do
        printf '<outline type="rss" text="%s" title="%s" xmlUrl="%s" htmlUrl="%s" />\n' \
          "$(printf '%s' "$title" | esc)" "$(printf '%s' "$title" | esc)" \
          "$(printf '%s' "$feed"  | esc)" "$(printf '%s' "$home"  | esc)"
      done
  echo '</body></opml>'
} > "$OPML"

# --- Sanitized public sample (safe to commit) ---
# Excludes anything that looks private: tokenized feed URLs (query strings or
# known member-feed hosts) and personalized/premium titles. Conservative on
# purpose — REVIEW the output before committing.
sqlite3 -json "$DB" "
  SELECT ZTITLE       AS title,
         ${AUTHOR}    AS author,
         ZFEEDURL     AS feedUrl,
         ZWEBPAGEURL  AS homeUrl,
         ${IMAGE}     AS artworkUrl,
         ${CATEGORY}  AS category
  FROM ZMTPODCAST
  WHERE ZFEEDURL IS NOT NULL
    AND ZFEEDURL NOT LIKE '%?%'                       -- no query tokens
    AND lower(ZFEEDURL) NOT LIKE '%supercast%'
    AND lower(ZFEEDURL) NOT LIKE '%supportingcast%'
    AND lower(ZFEEDURL) NOT LIKE '%supportingcast.fm%'
    AND lower(ZFEEDURL) NOT LIKE '%memberful%'
    AND lower(ZFEEDURL) NOT LIKE '%patreon%'
    AND lower(ZFEEDURL) NOT LIKE '%/private%'
    AND lower(coalesce(ZTITLE,'')) NOT LIKE '%(for %'
    AND lower(coalesce(ZTITLE,'')) NOT LIKE '%partner%'
    AND lower(coalesce(ZTITLE,'')) NOT LIKE '%premium%'
    AND lower(coalesce(ZTITLE,'')) NOT LIKE '%member%'
    AND lower(coalesce(ZTITLE,'')) NOT LIKE '%ad-free%'
    AND lower(coalesce(ZTITLE,'')) NOT LIKE '%ad free%'
    AND lower(coalesce(ZTITLE,'')) NOT LIKE '%subscriber%'
    AND lower(coalesce(ZTITLE,'')) NOT LIKE '%bonus%'
  ORDER BY ZTITLE COLLATE NOCASE
  LIMIT 15;
" > "$SAMPLE"

N=$(sqlite3 "$DB" "SELECT COUNT(*) FROM ZMTPODCAST WHERE ZFEEDURL IS NOT NULL;")
S=$(grep -c '"feedUrl"' "$SAMPLE" || true)
echo "Wrote ${N} subscriptions (full, local-only):"
echo "  ${JSON}"
echo "  ${OPML}"
echo "Wrote ${S} sanitized public shows (safe to commit):"
echo "  ${SAMPLE}"
echo
echo "IMPORTANT: open ${SAMPLE} and confirm no personal/member feeds slipped through before committing."

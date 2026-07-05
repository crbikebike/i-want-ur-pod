// FeedParsingKit — RSS/iTunes podcast feed parsing + upsert.
// Field mapping source of truth: docs/spec/feed-field-mapping.md
//
// Layering (see individual files for detail):
//  - ParsedFeed / ParsedEpisode / FeedError: pure value types, no SwiftData.
//  - FeedParser: streaming XMLParser decode of a feed body → ParsedFeed.
//  - FeedFetcher: URLSession fetch entry point, maps HTTP/network failures
//    to FeedError and hands successful bodies to FeedParser.
//  - FeedUpsert: the only file in this target that imports SwiftData —
//    matches/creates Podcast + Episode rows from a ParsedFeed.
public enum FeedParsingKit {}

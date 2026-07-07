// FeedUpsert — SwiftData persistence layer. The only file in this target
// that imports SwiftData/PodcastModels.
// Upsert rule source of truth: docs/spec/feed-field-mapping.md
// ("Re-parse / upsert rule").
import Foundation
import SwiftData
import PodcastModels

/// Persists a ``ParsedFeed`` as a `Podcast` + `[Episode]`, matching existing
/// rows by identity so re-parsing the same feed is idempotent.
public enum FeedUpsert {
    /// Upserts `feed` into `context`.
    ///
    /// Matches an existing `Podcast` by `feedURL` and existing `Episode`s by
    /// `guid`. Feed-derived fields are updated on match; new episodes are
    /// inserted. User-owned fields (`isSubscribed`, `dateAdded`,
    /// `downloadState`, `playbackProgress`) are never written by this
    /// function — they're either left at their model defaults (new rows) or
    /// preserved untouched (existing rows).
    ///
    /// - Throws: whatever `context.fetch` throws on a lookup failure.
    @MainActor
    public static func upsert(_ feed: ParsedFeed, into context: ModelContext) throws -> Podcast {
        let feedURL = feed.feedURL
        let podcastDescriptor = FetchDescriptor<Podcast>(
            predicate: #Predicate { $0.feedURL == feedURL }
        )
        let podcast: Podcast
        if let existing = try context.fetch(podcastDescriptor).first {
            podcast = existing
            podcast.title = feed.title
            podcast.author = feed.author
            podcast.homeURL = feed.homeURL
            podcast.artworkURL = feed.artworkURL
            podcast.category = feed.category
            podcast.summary = feed.summary
            // isSubscribed / dateAdded are user-owned — left untouched.
        } else {
            podcast = Podcast(
                title: feed.title,
                author: feed.author,
                feedURL: feed.feedURL,
                homeURL: feed.homeURL,
                artworkURL: feed.artworkURL,
                category: feed.category,
                summary: feed.summary
            )
            context.insert(podcast)
        }

        var existingByGuid: [String: Episode] = [:]
        for episode in podcast.episodes {
            existingByGuid[episode.guid] = episode
        }
        // Guids already handled during THIS upsert — guards against a feed
        // that lists the same guid twice creating two rows that violate
        // Episode's `@Attribute(.unique) guid` (which throws on save). The
        // first occurrence wins; later duplicates in the same batch are
        // ignored (keep-first).
        var handledThisBatch: Set<String> = []

        for parsedEpisode in feed.episodes {
            if handledThisBatch.contains(parsedEpisode.guid) {
                continue
            }
            handledThisBatch.insert(parsedEpisode.guid)

            if let existing = existingByGuid[parsedEpisode.guid] {
                existing.title = parsedEpisode.title
                existing.summary = parsedEpisode.summary
                existing.publishDate = parsedEpisode.publishDate
                existing.duration = parsedEpisode.duration
                existing.audioURL = parsedEpisode.audioURL
                existing.remoteArtworkURL = parsedEpisode.remoteArtworkURL
                existing.isExplicit = parsedEpisode.isExplicit
                existing.season = parsedEpisode.season
                existing.episodeNumber = parsedEpisode.episodeNumber
                existing.episodeType = parsedEpisode.episodeType
                // downloadState / playbackProgress are user-owned — left untouched.
            } else {
                let episode = Episode(
                    guid: parsedEpisode.guid,
                    title: parsedEpisode.title,
                    summary: parsedEpisode.summary,
                    publishDate: parsedEpisode.publishDate,
                    duration: parsedEpisode.duration,
                    audioURL: parsedEpisode.audioURL,
                    remoteArtworkURL: parsedEpisode.remoteArtworkURL,
                    isExplicit: parsedEpisode.isExplicit,
                    season: parsedEpisode.season,
                    episodeNumber: parsedEpisode.episodeNumber,
                    episodeType: parsedEpisode.episodeType,
                    podcast: podcast
                )
                context.insert(episode)
                podcast.episodes.append(episode)
                // Track for match on the NEXT upsert (already guarded within
                // this batch by handledThisBatch above).
                existingByGuid[parsedEpisode.guid] = episode
            }
        }

        // NOTE (E0): episodes that disappear upstream from the feed are
        // intentionally NOT pruned here — existing rows persist as-is.
        // Pruning/orphan handling is deferred (not an oversight).

        return podcast
    }
}

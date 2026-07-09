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

        // Self-heal any content-duplicate rows already persisted (a feed that
        // lists one real episode twice under different guids — same audio —
        // would have created two rows before this dedupe shipped, e.g. Bone
        // Valley's re-ingested Season 3). Collapse each `audioURL` group to a
        // single survivor, preferring the copy the user has touched so queue /
        // download / progress state is never severed.
        pruneAudioDuplicates(of: podcast, in: context)

        var existingByGuid: [String: Episode] = [:]
        var existingByAudioURL: [URL: Episode] = [:]
        for episode in podcast.episodes {
            existingByGuid[episode.guid] = episode
            existingByAudioURL[episode.audioURL] = episode
        }
        // Identities already handled during THIS upsert. `handledGuids` guards
        // against a feed that lists the same guid twice creating two rows that
        // violate Episode's `@Attribute(.unique) guid` (which throws on save).
        // `handledAudioURLs` extends the same keep-first guard to items that
        // share an audio URL under different guids — one real episode. First
        // occurrence wins; later duplicates in the batch are ignored.
        var handledGuids: Set<String> = []
        var handledAudioURLs: Set<URL> = []

        for parsedEpisode in feed.episodes {
            if handledGuids.contains(parsedEpisode.guid) || handledAudioURLs.contains(parsedEpisode.audioURL) {
                continue
            }
            handledGuids.insert(parsedEpisode.guid)
            handledAudioURLs.insert(parsedEpisode.audioURL)

            // A new guid whose audio already belongs to a persisted episode is
            // the same episode re-issued under a fresh guid: update that
            // surviving row's feed-derived fields instead of inserting a
            // second one, so the re-issue never re-enters. The row keeps its
            // original guid (a stable identity for user-owned state).
            if existingByGuid[parsedEpisode.guid] == nil,
               let sameAudio = existingByAudioURL[parsedEpisode.audioURL] {
                apply(parsedEpisode, to: sameAudio, keepingGuid: true)
                continue
            }

            if let existing = existingByGuid[parsedEpisode.guid] {
                apply(parsedEpisode, to: existing, keepingGuid: false)
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
                // this batch by handledGuids / handledAudioURLs above).
                existingByGuid[parsedEpisode.guid] = episode
                existingByAudioURL[parsedEpisode.audioURL] = episode
            }
        }

        // NOTE (E0): episodes that disappear upstream from the feed are
        // intentionally NOT pruned here — existing rows persist as-is.
        // Pruning/orphan handling is deferred (not an oversight).

        return podcast
    }

    /// Copies the feed-derived fields of `parsed` onto `episode`. User-owned
    /// fields (`downloadState`, `playbackProgress`) are never touched. When
    /// `keepingGuid` is true the episode's `guid` is left as-is — used when a
    /// re-issued item (new guid, same audio) folds onto an existing row so its
    /// stable identity, and the user state keyed to it, is preserved.
    @MainActor
    private static func apply(_ parsed: ParsedEpisode, to episode: Episode, keepingGuid: Bool) {
        if !keepingGuid { episode.guid = parsed.guid }
        episode.title = parsed.title
        episode.summary = parsed.summary
        episode.publishDate = parsed.publishDate
        episode.duration = parsed.duration
        episode.audioURL = parsed.audioURL
        episode.remoteArtworkURL = parsed.remoteArtworkURL
        episode.isExplicit = parsed.isExplicit
        episode.season = parsed.season
        episode.episodeNumber = parsed.episodeNumber
        episode.episodeType = parsed.episodeType
    }

    /// Collapses any group of persisted episodes that share an `audioURL` down
    /// to a single survivor, deleting the rest. This heals stores that already
    /// hold content-duplicate rows (one real episode listed under two guids —
    /// see the Bone Valley Season 3 case). The survivor is the copy the user
    /// has touched — downloaded, partially played, or queued — falling back to
    /// the first seen, so a `QueueItem`'s `.nullify` reference is never orphaned
    /// by deleting the episode it points at.
    @MainActor
    private static func pruneAudioDuplicates(of podcast: Podcast, in context: ModelContext) {
        var byAudioURL: [URL: [Episode]] = [:]
        for episode in podcast.episodes {
            byAudioURL[episode.audioURL, default: []].append(episode)
        }
        for (_, group) in byAudioURL where group.count > 1 {
            let survivor = group.first { hasUserState($0) } ?? group[0]
            for duplicate in group where duplicate !== survivor {
                podcast.episodes.removeAll { $0 === duplicate }
                context.delete(duplicate)
            }
        }
    }

    /// Whether the user has interacted with `episode` — the signal the prune
    /// tie-break protects (downloaded, played into, or sitting in the queue).
    @MainActor
    private static func hasUserState(_ episode: Episode) -> Bool {
        episode.downloadState.isDownloaded || episode.playbackProgress > 0 || !episode.queueItems.isEmpty
    }
}

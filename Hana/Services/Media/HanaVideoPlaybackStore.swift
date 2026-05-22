import AVFoundation
import Foundation

@MainActor
final class HanaVideoPlaybackStore {
    struct Entry {
        let linkID: String
        let url: URL
        let player: AVPlayer
        let item: AVPlayerItem
        let asset: AVAsset
    }

    private struct StoredEntry {
        let entry: Entry
        var lastAccessedAt: Date
    }

    private let maximumEntryCount = 1
    private var entries: [String: StoredEntry] = [:]
    private var activeVideoCode: String?

    func entry(
        videoCode: String,
        link: ResolutionLink,
        headers: [String: String],
        resumeTime: TimeInterval
    ) -> (entry: Entry, isReused: Bool) {
        activeVideoCode = videoCode
        if var stored = entries[videoCode],
           stored.entry.linkID == link.id,
           stored.entry.url == link.url {
            stored.lastAccessedAt = .now
            entries[videoCode] = stored
            return (stored.entry, true)
        }

        let asset = AVURLAsset(
            url: link.url,
            options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
        )
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.isMuted = false
        player.volume = 1.0
        if resumeTime > 1 {
            player.seek(
                to: CMTime(seconds: resumeTime, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        }

        let entry = Entry(
            linkID: link.id,
            url: link.url,
            player: player,
            item: item,
            asset: asset
        )
        entries[videoCode] = StoredEntry(entry: entry, lastAccessedAt: .now)
        removeOldEntriesIfNeeded(excluding: videoCode)
        return (entry, false)
    }

    func remove(videoCode: String) {
        if let stored = entries[videoCode] {
            dispose(stored)
        }
        entries.removeValue(forKey: videoCode)
        if activeVideoCode == videoCode {
            activeVideoCode = nil
        }
    }

    func removeAll() {
        entries.values.forEach(dispose)
        entries.removeAll()
        activeVideoCode = nil
    }

    func trimForMemoryPressure() {
        let protectedVideoCode = activeVideoCode
        for videoCode in Array(entries.keys) where videoCode != protectedVideoCode {
            if let stored = entries[videoCode] {
                dispose(stored)
            }
            entries.removeValue(forKey: videoCode)
        }
        removeOldEntriesIfNeeded(excluding: protectedVideoCode)
    }

    private func removeOldEntriesIfNeeded(excluding currentVideoCode: String?) {
        while entries.count > maximumEntryCount {
            guard let oldest = entries
                .filter({ $0.key != currentVideoCode })
                .min(by: { $0.value.lastAccessedAt < $1.value.lastAccessedAt })?
                .key else {
                return
            }
            if let stored = entries[oldest] {
                dispose(stored)
            }
            entries.removeValue(forKey: oldest)
        }
    }

    private func dispose(_ stored: StoredEntry) {
        stored.entry.player.pause()
        stored.entry.player.replaceCurrentItem(with: nil)
    }
}

import AVKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

extension HanimeAccountVideoList {
    func merging(_ next: HanimeAccountVideoList) -> HanimeAccountVideoList {
        return HanimeAccountVideoList(
            videos: (videos + next.videos).deduplicatedByVideoCode(),
            description: description ?? next.description,
            csrfToken: next.csrfToken ?? csrfToken,
            maxPage: max(maxPage, next.maxPage)
        )
    }
}

extension HanimePlaylistsPage {
    func merging(_ next: HanimePlaylistsPage) -> HanimePlaylistsPage {
        var seen = Set(playlists.map(\.listCode))
        let newPlaylists = next.playlists.filter { seen.insert($0.listCode).inserted }
        return HanimePlaylistsPage(
            playlists: playlists + newPlaylists,
            csrfToken: next.csrfToken ?? csrfToken,
            maxPage: max(maxPage, next.maxPage)
        )
    }
}

extension HanimeSubscriptionsPage {
    func merging(_ next: HanimeSubscriptionsPage) -> HanimeSubscriptionsPage {
        var seenArtists = Set(artists.map(\.id))
        let newArtists = next.artists.filter { seenArtists.insert($0.id).inserted }
        return HanimeSubscriptionsPage(
            artists: artists + newArtists,
            videos: (videos + next.videos).deduplicatedByVideoCode(),
            csrfToken: next.csrfToken ?? csrfToken,
            maxPage: max(maxPage, next.maxPage)
        )
    }
}

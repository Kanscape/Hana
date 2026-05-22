import AVKit
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

extension HanimeAccountVideoList {
    func merging(_ next: HanimeAccountVideoList) -> HanimeAccountVideoList {
        var seen = Set(videos.map(\.videoCode))
        let newVideos = next.videos.filter { seen.insert($0.videoCode).inserted }
        return HanimeAccountVideoList(
            videos: videos + newVideos,
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
        var seenVideos = Set(videos.map(\.videoCode))
        let newArtists = next.artists.filter { seenArtists.insert($0.id).inserted }
        let newVideos = next.videos.filter { seenVideos.insert($0.videoCode).inserted }
        return HanimeSubscriptionsPage(
            artists: artists + newArtists,
            videos: videos + newVideos,
            csrfToken: next.csrfToken ?? csrfToken,
            maxPage: max(maxPage, next.maxPage)
        )
    }
}

import Foundation
import Nuke
import Observation
#if os(iOS)
import UIKit
#endif

@Observable
final class HanaServices {
    let httpClient: HanaHTTPClient
    let imagePipeline: ImagePipeline
    let siteSession: SiteWebSession
    let repository: HanimeRepository
    let downloadClient: HanimeDownloadClient
    let networkMonitor: HanaNetworkMonitor
    let profileAvatarStore: HanaProfileAvatarStore
    let videoPlaybackStore: HanaVideoPlaybackStore
#if os(iOS)
    @ObservationIgnored private var memoryWarningObserver: NSObjectProtocol?
#endif

    init(baseURL: URL = HanaServices.configuredBaseURL()) {
        let httpClient = HanaHTTPClient(baseURL: baseURL)
        let imagePipeline = HanaImagePipeline.make()
        let parser = HanimeHTMLParser(baseURL: baseURL)
        self.httpClient = httpClient
        self.imagePipeline = imagePipeline
        self.siteSession = SiteWebSession(baseURL: baseURL)
        self.repository = HanimeRepository(httpClient: httpClient, parser: parser)
        self.downloadClient = HanimeDownloadClient(httpClient: httpClient)
        self.networkMonitor = HanaNetworkMonitor()
        self.videoPlaybackStore = HanaVideoPlaybackStore()
        self.profileAvatarStore = HanaProfileAvatarStore(
            imagePipeline: imagePipeline,
            makeImageURLRequest: httpClient.imageURLRequest(for:cachePolicy:timeoutInterval:)
        )
#if os(iOS)
        self.memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [repository, videoPlaybackStore] _ in
            repository.clearVideoCache()
            Task { @MainActor in
                videoPlaybackStore.trimForMemoryPressure()
            }
        }
#endif
    }

    func applyLoginState(user: HanimeUserProfile?) async {
        repository.clearVideoCache()
        siteSession.updateLoginState(user: user)
        await profileAvatarStore.refreshAvatar(from: user?.avatarURL, ownerID: user?.id)
    }

    func logout() {
        repository.clearVideoCache()
        videoPlaybackStore.removeAll()
        siteSession.logout()
        profileAvatarStore.clear()
    }

    static func configuredBaseURL(defaults: UserDefaults = .standard) -> URL {
        let stored = defaults.string(forKey: HanaSettingsKey.siteBaseURL) ?? HanaSiteBaseURL.defaultValue
        let normalized = HanaSiteBaseURL.normalized(stored) ?? HanaSiteBaseURL.defaultValue
        if normalized != stored {
            defaults.set(normalized, forKey: HanaSettingsKey.siteBaseURL)
        }
        return URL(string: normalized) ?? URL(string: HanaSiteBaseURL.defaultValue)!
    }
}

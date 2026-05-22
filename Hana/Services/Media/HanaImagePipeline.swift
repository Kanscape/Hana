import Foundation
import Nuke

enum HanaImagePipeline {
    static func make() -> ImagePipeline {
        var configuration = ImagePipeline.Configuration.withDataCache(
            name: "Hana.ImageDataCache",
            sizeLimit: 150 * 1024 * 1024
        )

        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.httpShouldSetCookies = true
        sessionConfiguration.httpCookieAcceptPolicy = .always
        sessionConfiguration.httpCookieStorage = .shared
        sessionConfiguration.requestCachePolicy = .useProtocolCachePolicy
        sessionConfiguration.connectionProxyDictionary = HanaNetworkProxySettings.current().connectionProxyDictionary
        sessionConfiguration.urlCache = nil

        configuration.dataLoader = DataLoader(configuration: sessionConfiguration)
        configuration.isProgressiveDecodingEnabled = true
        return ImagePipeline(configuration: configuration)
    }
}

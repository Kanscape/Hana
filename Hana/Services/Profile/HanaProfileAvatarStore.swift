import Foundation
import Nuke
import Observation

#if canImport(UIKit)
import UIKit
#endif

@Observable
final class HanaProfileAvatarStore {
    private(set) var imageData: Data?

    private let defaults: UserDefaults
    private let fileManager: FileManager
    @ObservationIgnored private let imagePipeline: ImagePipeline
    @ObservationIgnored private let makeImageURLRequest: (URL, URLRequest.CachePolicy, TimeInterval) -> URLRequest
    private let avatarURLStringKey = "Hana.ProfileAvatarStore.avatarURLString"
    private let ownerIDKey = "Hana.ProfileAvatarStore.ownerID"
    private let avatarPointSizeKey = "Hana.ProfileAvatarStore.avatarPointSize"
    private let fileName = "ProfileTabAvatar.png"
    static let tabIconPointSize: CGFloat = 25
    static let tabIconImageScale: CGFloat = 3
    private static let targetPointSize = tabIconPointSize

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        imagePipeline: ImagePipeline = .shared,
        makeImageURLRequest: @escaping (URL, URLRequest.CachePolicy, TimeInterval) -> URLRequest = { url, cachePolicy, timeoutInterval in
            var request = URLRequest(url: url)
            request.cachePolicy = cachePolicy
            request.timeoutInterval = timeoutInterval
            return request
        }
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.imagePipeline = imagePipeline
        self.makeImageURLRequest = makeImageURLRequest
        let cachedPointSize = defaults.double(forKey: avatarPointSizeKey)
        if cachedPointSize > 0, abs(cachedPointSize - Self.targetPointSize) > 0.1 {
            clear()
        }
        loadCachedImage()
    }

    func refreshAvatar(from avatarURL: URL?, ownerID: String?) async {
        guard let avatarURL else {
            clear()
            return
        }

        let ownerID = ownerID ?? ""
        let cachedURLString = defaults.string(forKey: avatarURLStringKey)
        let cachedOwnerID = defaults.string(forKey: ownerIDKey)
        if cachedURLString != avatarURL.absoluteString || cachedOwnerID != ownerID {
            removeCachedFile()
            imageData = nil
        }

        do {
            let urlRequest = makeImageURLRequest(
                avatarURL,
                .reloadIgnoringLocalCacheData,
                15
            )
            let request = ImageRequest(urlRequest: urlRequest, options: [.reloadIgnoringCachedData])
            let (data, _) = try await imagePipeline.data(for: request)
            guard let normalizedData = Self.normalizedAvatarData(from: data) else {
                loadCachedImage()
                return
            }

            let existingData = avatarFileURL.flatMap { try? Data(contentsOf: $0) }
            guard existingData != normalizedData || imageData == nil else {
                defaults.set(avatarURL.absoluteString, forKey: avatarURLStringKey)
                defaults.set(ownerID, forKey: ownerIDKey)
                imageData = normalizedData
                return
            }

            guard let avatarFileURL else { return }
            try normalizedData.write(to: avatarFileURL, options: .atomic)
            defaults.set(avatarURL.absoluteString, forKey: avatarURLStringKey)
            defaults.set(ownerID, forKey: ownerIDKey)
            defaults.set(Self.targetPointSize, forKey: avatarPointSizeKey)
            imageData = normalizedData
        } catch {
            loadCachedImage()
        }
    }

    func clear() {
        removeCachedFile()
        defaults.removeObject(forKey: avatarURLStringKey)
        defaults.removeObject(forKey: ownerIDKey)
        defaults.removeObject(forKey: avatarPointSizeKey)
        imageData = nil
    }

    private func loadCachedImage() {
        imageData = avatarFileURL.flatMap { try? Data(contentsOf: $0) }
    }

    private func removeCachedFile() {
        guard let avatarFileURL else { return }
        try? fileManager.removeItem(at: avatarFileURL)
    }

    private var avatarFileURL: URL? {
        guard let directory = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }
        return directory.appendingPathComponent(fileName)
    }

    private static func normalizedAvatarData(from data: Data) -> Data? {
#if canImport(UIKit)
        guard let image = UIImage(data: data),
              image.size.width > 0,
              image.size.height > 0 else {
            return nil
        }
        let size = CGSize(width: targetPointSize, height: targetPointSize)
        let format = UIGraphicsImageRendererFormat()
        format.scale = Self.tabIconImageScale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.pngData { _ in
            let bounds = CGRect(origin: .zero, size: size)
            UIBezierPath(ovalIn: bounds).addClip()
            let scale = max(size.width / image.size.width, size.height / image.size.height)
            let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = CGPoint(
                x: (size.width - drawSize.width) / 2,
                y: (size.height - drawSize.height) / 2
            )
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
#else
        data
#endif
    }
}

#if canImport(UIKit) && os(iOS)
import UIKit

typealias HanaInterfaceOrientationMask = UIInterfaceOrientationMask

enum HanaInterfaceOrientationController {
    private static let normalMask: HanaInterfaceOrientationMask = UIDevice.current.userInterfaceIdiom == .pad ? .all : .portrait
    private static var currentMask: HanaInterfaceOrientationMask = normalMask
    private static var isVideoFullscreenActive = false
    private static var preparationTask: Task<Void, Never>?

    static var supportedInterfaceOrientations: HanaInterfaceOrientationMask {
        currentMask
    }

    static func prepareVideoFullscreen(_ mask: HanaInterfaceOrientationMask) {
        preparationTask?.cancel()
        currentMask = mask
        preparationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1800))
            guard !Task.isCancelled, !isVideoFullscreenActive else { return }
            if currentMask == mask {
                currentMask = normalMask
                request(normalMask)
            }
        }
    }

    static func cancelVideoFullscreenPreparation() {
        preparationTask?.cancel()
        guard !isVideoFullscreenActive, currentMask != normalMask else { return }
        currentMask = normalMask
        request(normalMask)
    }

    static func enterVideoFullscreen(_ mask: HanaInterfaceOrientationMask) {
        preparationTask?.cancel()
        isVideoFullscreenActive = true
        currentMask = mask
        request(mask)
    }

    static func exitVideoFullscreen() {
        preparationTask?.cancel()
        isVideoFullscreenActive = false
        currentMask = normalMask
        request(normalMask)
    }

    static func refreshCurrentOrientationMask() {
        request(currentMask)
    }

    private static func request(_ mask: HanaInterfaceOrientationMask) {
        for scene in activeWindowScenes {
            updateSupportedInterfaceOrientations(in: scene)
            scene.requestGeometryUpdate(
                UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: mask),
                errorHandler: { _ in }
            )
        }
    }

    private static var activeWindowScenes: [UIWindowScene] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
    }

    private static func updateSupportedInterfaceOrientations(in scene: UIWindowScene) {
        for window in scene.windows {
            updateSupportedInterfaceOrientations(from: window.rootViewController)
        }
    }

    private static func updateSupportedInterfaceOrientations(from controller: UIViewController?) {
        guard let controller else { return }
        controller.setNeedsUpdateOfSupportedInterfaceOrientations()
        if #available(iOS 26.0, *) {
            controller.setNeedsUpdateOfPrefersInterfaceOrientationLocked()
        }
        for child in controller.children {
            updateSupportedInterfaceOrientations(from: child)
        }
        updateSupportedInterfaceOrientations(from: controller.presentedViewController)
    }
}
#else
struct HanaInterfaceOrientationMask: Hashable {
    static let portrait = HanaInterfaceOrientationMask()
    static let landscape = HanaInterfaceOrientationMask()
}

enum HanaInterfaceOrientationController {
    static func prepareVideoFullscreen(_ mask: HanaInterfaceOrientationMask) {}
    static func cancelVideoFullscreenPreparation() {}
    static func enterVideoFullscreen(_ mask: HanaInterfaceOrientationMask) {}
    static func exitVideoFullscreen() {}
    static func refreshCurrentOrientationMask() {}
}
#endif

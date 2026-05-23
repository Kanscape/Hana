import AVFoundation
import AVKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum HanaVideoFullscreenOrientation: Hashable {
    case portrait
    case landscape

    var interfaceMask: HanaInterfaceOrientationMask {
        switch self {
        case .portrait:
            .portrait
        case .landscape:
            .landscape
        }
    }
}

#if canImport(UIKit)
struct HanaAVPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer?
    let allowsPictureInPicture: Bool
    var exitsFullScreenWhenPlaybackEnds = true
    let gestureConfiguration: HanaPlayerGestureConfiguration
    var fullscreenStatusOverlay: AnyView? = nil
    var onFullscreenChange: (Bool) -> Void = { _ in }
    var onPotentialFullscreenIntent: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        configure(controller, context: context)
        context.coordinator.onFullscreenChange = onFullscreenChange
        context.coordinator.onPotentialFullscreenIntent = onPotentialFullscreenIntent
        context.coordinator.installGestures(on: controller)
        context.coordinator.updateGestureConfiguration(gestureConfiguration)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        configure(controller, context: context)
        context.coordinator.onFullscreenChange = onFullscreenChange
        context.coordinator.onPotentialFullscreenIntent = onPotentialFullscreenIntent
        context.coordinator.updateGestureConfiguration(gestureConfiguration)
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        if coordinator.isFullscreenActive {
            coordinator.retainUntilFullscreenEnds(controller)
        } else {
            coordinator.removeFullscreenOverlay()
            controller.delegate = nil
        }
    }

    private func configure(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
        controller.delegate = context.coordinator
        controller.allowsPictureInPicturePlayback = allowsPictureInPicture
        controller.canStartPictureInPictureAutomaticallyFromInline = allowsPictureInPicture
        controller.showsPlaybackControls = true
        controller.requiresLinearPlayback = false
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = exitsFullScreenWhenPlaybackEnds
        context.coordinator.updateFullscreenStatusOverlay(fullscreenStatusOverlay, on: controller)
    }

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate, UIGestureRecognizerDelegate {
        var onFullscreenChange: (Bool) -> Void = { _ in }
        var onPotentialFullscreenIntent: () -> Void = {}
        private(set) var isFullscreenActive = false
        private weak var playerViewController: AVPlayerViewController?
        private var retainedFullscreenController: AVPlayerViewController?
        private var wasDismantledDuringFullscreen = false
        private var gestureConfiguration: HanaPlayerGestureConfiguration = .defaultValue
        private var controlTouchRecognizer: UITapGestureRecognizer?
        private var longPressRecognizer: UILongPressGestureRecognizer?
        private var longPressWasPlaying = false
        private var longPressBaseRate: Float = 1
        private var isLongPressSpeedActive = false
        private var currentFullscreenStatusOverlay: AnyView?
        private var fullscreenStatusHost: UIHostingController<AnyView>?
        private var fullscreenStatusConstraints: [NSLayoutConstraint] = []

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willBeginFullScreenPresentationWithAnimationCoordinator transitionCoordinator: any UIViewControllerTransitionCoordinator
        ) {
            HanaAVPlayerFullscreenState.begin()
            isFullscreenActive = true
            reinstallFullscreenStatusOverlay(on: playerViewController)
            setFullscreenStatusOverlayVisible(true)
            onFullscreenChange(true)
            transitionCoordinator.animate(alongsideTransition: nil) { [weak self] context in
                guard let self else { return }
                if context.isCancelled {
                    HanaAVPlayerFullscreenState.end()
                    self.isFullscreenActive = false
                    self.setFullscreenStatusOverlayVisible(false)
                    self.onFullscreenChange(false)
                    self.releaseAfterFullscreenIfNeeded()
                } else {
                    self.reinstallFullscreenStatusOverlay(on: playerViewController)
                    self.setFullscreenStatusOverlayVisible(true)
                }
            }
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willEndFullScreenPresentationWithAnimationCoordinator transitionCoordinator: any UIViewControllerTransitionCoordinator
        ) {
            let player = playerViewController.player
            let shouldResumePlayback = (player?.rate ?? 0) > 0
                || player?.timeControlStatus == .playing
                || player?.timeControlStatus == .waitingToPlayAtSpecifiedRate
            let resumeRate = max(player?.rate ?? 1, 1)
            transitionCoordinator.animate(alongsideTransition: nil) { [weak self] _ in
                guard let self else { return }
                if transitionCoordinator.isCancelled {
                    self.isFullscreenActive = true
                    self.setFullscreenStatusOverlayVisible(true)
                    self.onFullscreenChange(true)
                    return
                }
                self.isFullscreenActive = false
                self.setFullscreenStatusOverlayVisible(false)
                if shouldResumePlayback {
                    player?.playImmediately(atRate: resumeRate)
                }
                HanaAVPlayerFullscreenState.end()
                self.onFullscreenChange(false)
                self.releaseAfterFullscreenIfNeeded()
            }
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            restoreUserInterfaceForFullScreenExitWithCompletionHandler completionHandler: @escaping @Sendable (Bool) -> Void
        ) {
            completionHandler(true)
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
        ) {
            completionHandler(true)
        }

        func installGestures(on controller: AVPlayerViewController) {
            self.playerViewController = controller
            guard controlTouchRecognizer == nil,
                  longPressRecognizer == nil else {
                return
            }

            let controlTouch = UITapGestureRecognizer(target: self, action: #selector(handleControlTouchProbe(_:)))
            controlTouch.cancelsTouchesInView = false
            controlTouch.delaysTouchesBegan = false
            controlTouch.delaysTouchesEnded = false
            controlTouch.delegate = self
            controller.view.addGestureRecognizer(controlTouch)
            controlTouchRecognizer = controlTouch

            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            longPress.minimumPressDuration = 0.35
            longPress.cancelsTouchesInView = false
            longPress.delegate = self
            controller.view.addGestureRecognizer(longPress)
            longPressRecognizer = longPress
        }

        func updateGestureConfiguration(_ configuration: HanaPlayerGestureConfiguration) {
            gestureConfiguration = configuration.normalized
            longPressRecognizer?.isEnabled = true
        }

        func updateFullscreenStatusOverlay(_ overlay: AnyView?, on controller: AVPlayerViewController) {
            playerViewController = controller
            currentFullscreenStatusOverlay = overlay
            guard let overlayContainer = controller.contentOverlayView else {
                removeFullscreenOverlay()
                return
            }
            updateFullscreenStatusOverlay(overlay, on: controller, in: overlayContainer)
        }

        private func reinstallFullscreenStatusOverlay(on controller: AVPlayerViewController) {
            updateFullscreenStatusOverlay(currentFullscreenStatusOverlay, on: controller)
        }

        private func setFullscreenStatusOverlayVisible(_ isVisible: Bool) {
            fullscreenStatusHost?.view.isHidden = !isVisible
            if isVisible {
                if let statusView = fullscreenStatusHost?.view {
                    statusView.superview?.bringSubviewToFront(statusView)
                }
            }
        }

        private func updateFullscreenStatusOverlay(
            _ overlay: AnyView?,
            on controller: AVPlayerViewController,
            in overlayContainer: UIView
        ) {
            guard let overlay else {
                removeFullscreenStatusOverlay()
                return
            }

            if let fullscreenStatusHost {
                fullscreenStatusHost.rootView = overlay
                if fullscreenStatusHost.view.superview !== overlayContainer {
                    NSLayoutConstraint.deactivate(fullscreenStatusConstraints)
                    fullscreenStatusConstraints.removeAll()
                    fullscreenStatusHost.view.removeFromSuperview()
                    attachFullscreenStatusHost(fullscreenStatusHost, to: overlayContainer)
                }
                fullscreenStatusHost.view.isHidden = !isFullscreenActive
                return
            }

            let host = UIHostingController(rootView: overlay)
            host.view.backgroundColor = .clear
            host.view.translatesAutoresizingMaskIntoConstraints = false
            host.view.isUserInteractionEnabled = false
            host.view.isHidden = !isFullscreenActive

            attachFullscreenStatusHost(host, to: overlayContainer)
            fullscreenStatusHost = host
        }

        private func attachFullscreenStatusHost(
            _ host: UIHostingController<AnyView>,
            to overlayContainer: UIView
        ) {
            overlayContainer.addSubview(host.view)
            fullscreenStatusConstraints = [
                host.view.leadingAnchor.constraint(equalTo: overlayContainer.safeAreaLayoutGuide.leadingAnchor),
                host.view.trailingAnchor.constraint(equalTo: overlayContainer.safeAreaLayoutGuide.trailingAnchor),
                host.view.topAnchor.constraint(equalTo: overlayContainer.safeAreaLayoutGuide.topAnchor),
                host.view.heightAnchor.constraint(equalToConstant: 120),
            ]
            NSLayoutConstraint.activate(fullscreenStatusConstraints)
            overlayContainer.bringSubviewToFront(host.view)
        }

        func removeFullscreenOverlay() {
            removeFullscreenStatusOverlay()
        }

        private func removeFullscreenStatusOverlay() {
            guard let fullscreenStatusHost else { return }
            NSLayoutConstraint.deactivate(fullscreenStatusConstraints)
            fullscreenStatusConstraints = []
            fullscreenStatusHost.view.removeFromSuperview()
            self.fullscreenStatusHost = nil
        }

        func retainUntilFullscreenEnds(_ controller: AVPlayerViewController) {
            wasDismantledDuringFullscreen = true
            retainedFullscreenController = controller
            HanaAVPlayerFullscreenRetainer.retain(self)
        }

        private func releaseAfterFullscreenIfNeeded() {
            if wasDismantledDuringFullscreen {
                removeFullscreenOverlay()
                retainedFullscreenController?.delegate = nil
            }
            retainedFullscreenController = nil
            wasDismantledDuringFullscreen = false
            HanaAVPlayerFullscreenRetainer.release(self)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if gestureRecognizer === controlTouchRecognizer {
                if touchTargetsPotentialFullscreenControl(touch.view) {
                    onPotentialFullscreenIntent()
                }
                return false
            }
            if gestureRecognizer === longPressRecognizer, isFullscreenActive {
                return false
            }

            return !touchTargetsPlaybackControl(touch.view)
        }

        @objc private func handleControlTouchProbe(_ recognizer: UITapGestureRecognizer) {}

        @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began:
                beginLongPressSpeed()
            case .ended, .cancelled, .failed:
                endLongPressSpeed()
            default:
                break
            }
        }

        private func beginLongPressSpeed() {
            guard !isFullscreenActive else { return }
            guard let player = playerViewController?.player else { return }
            guard !isLongPressSpeedActive else { return }
            longPressWasPlaying = player.timeControlStatus == .playing || player.rate > 0
            guard longPressWasPlaying else { return }
            isLongPressSpeedActive = true
            longPressBaseRate = player.defaultRate > 0 ? player.defaultRate : 1
            player.rate = Float(gestureConfiguration.longPressRate)
        }

        private func endLongPressSpeed() {
            guard isLongPressSpeedActive else { return }
            isLongPressSpeedActive = false
            if longPressWasPlaying {
                playerViewController?.player?.rate = longPressBaseRate
            } else {
                playerViewController?.player?.pause()
            }
        }

        private func touchTargetsPlaybackControl(_ view: UIView?) -> Bool {
            var current = view
            while let candidate = current {
                if candidate is UIControl {
                    return true
                }
                let className = NSStringFromClass(type(of: candidate)).lowercased()
                if className.contains("button")
                    || className.contains("slider")
                    || className.contains("scrubber") {
                    return true
                }
                if candidate === playerViewController?.view {
                    return false
                }
                current = candidate.superview
            }
            return false
        }

        private func touchTargetsPotentialFullscreenControl(_ view: UIView?) -> Bool {
            var current = view
            while let candidate = current {
                if fullscreenControlDescriptorMatches(candidate) {
                    return true
                }
                if candidate === playerViewController?.view {
                    return false
                }
                current = candidate.superview
            }
            return false
        }

        private func fullscreenControlDescriptorMatches(_ view: UIView) -> Bool {
            let className = NSStringFromClass(type(of: view)).lowercased()
            if className.contains("fullscreen") || className.contains("full_screen") {
                return true
            }

            let descriptors = [
                view.accessibilityIdentifier,
                view.accessibilityLabel,
                view.accessibilityHint,
            ]
            return descriptors.contains { descriptor in
                guard let descriptor = descriptor?.lowercased() else { return false }
                return descriptor.contains("fullscreen")
                    || descriptor.contains("full screen")
                    || descriptor.contains("全屏")
                    || descriptor.contains("全螢幕")
                    || descriptor.contains("全萤幕")
            }
        }
    }
}
#elseif canImport(AppKit)
struct HanaAVPlayerView: NSViewRepresentable {
    let player: AVPlayer?
    let allowsPictureInPicture: Bool
    var exitsFullScreenWhenPlaybackEnds = true
    let gestureConfiguration: HanaPlayerGestureConfiguration
    var fullscreenStatusOverlay: AnyView? = nil
    var onFullscreenChange: (Bool) -> Void = { _ in }
    var onPotentialFullscreenIntent: () -> Void = {}

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player {
            view.player = player
        }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player = nil
    }
}
#endif

@MainActor
enum HanaAVPlayerFullscreenState {
    private static var activePresentationCount = 0

    static var isActive: Bool {
        activePresentationCount > 0
    }

    static func begin() {
        activePresentationCount += 1
    }

    static func end() {
        activePresentationCount = max(activePresentationCount - 1, 0)
    }
}

#if canImport(UIKit)
@MainActor
private enum HanaAVPlayerFullscreenRetainer {
    private static var coordinators: [ObjectIdentifier: AnyObject] = [:]

    static func retain(_ coordinator: HanaAVPlayerView.Coordinator) {
        coordinators[ObjectIdentifier(coordinator)] = coordinator
    }

    static func release(_ coordinator: HanaAVPlayerView.Coordinator) {
        coordinators.removeValue(forKey: ObjectIdentifier(coordinator))
    }
}
#endif

struct HanaPlayerGestureConfiguration: Equatable {
    var longPressRate: Double

    static let defaultValue = HanaPlayerGestureConfiguration(
        longPressRate: HanaPlaybackSpeedCatalog.defaultLongPressRate
    )

    var normalized: HanaPlayerGestureConfiguration {
        HanaPlayerGestureConfiguration(
            longPressRate: HanaPlaybackSpeedCatalog.normalizedLongPressRate(longPressRate)
        )
    }
}

extension HanaVideoFullscreenOrientation {
    static func resolved(for asset: AVAsset) async -> HanaVideoFullscreenOrientation {
        do {
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                return .landscape
            }
            let naturalSize = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let displaySize = naturalSize.applying(transform)
            return abs(displaySize.height) > abs(displaySize.width) ? .portrait : .landscape
        } catch {
            return .landscape
        }
    }
}

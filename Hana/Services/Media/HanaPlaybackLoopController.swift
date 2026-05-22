import AVFoundation
import Foundation

@MainActor
protocol HanaPlaybackLoopControllingPlayer: AnyObject {
    var currentItem: AVPlayerItem? { get }
    var actionAtItemEnd: AVPlayer.ActionAtItemEnd { get set }

    func seek(
        to time: CMTime,
        toleranceBefore: CMTime,
        toleranceAfter: CMTime,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    )

    func play()
}

extension AVPlayer: HanaPlaybackLoopControllingPlayer {}

@MainActor
final class HanaPlaybackLoopController {
    private let notificationCenter: NotificationCenter
    private weak var player: (any HanaPlaybackLoopControllingPlayer)?
    private weak var item: AVPlayerItem?
    private var endObserver: NSObjectProtocol?
    private var isLoopingEnabled = false
    private var onPlaybackEnded: @MainActor () -> Void = {}

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    deinit {
        if let endObserver {
            notificationCenter.removeObserver(endObserver)
        }
    }

    func configure(
        player: (any HanaPlaybackLoopControllingPlayer)?,
        item: AVPlayerItem?,
        isLoopingEnabled: Bool,
        onPlaybackEnded: @escaping @MainActor () -> Void = {}
    ) {
        self.player?.actionAtItemEnd = .pause
        removeEndObserver()
        self.player = player
        self.item = item
        self.isLoopingEnabled = isLoopingEnabled
        self.onPlaybackEnded = onPlaybackEnded
        player?.actionAtItemEnd = isLoopingEnabled ? .none : .pause

        guard isLoopingEnabled, let item else { return }
        endObserver = notificationCenter.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: nil
        ) { [weak self, weak item] _ in
            Task { @MainActor [weak self, weak item] in
                guard let item else { return }
                self?.restartPlaybackIfNeeded(for: item)
            }
        }
    }

    func invalidate() {
        removeEndObserver()
        player?.actionAtItemEnd = .pause
        player = nil
        item = nil
        isLoopingEnabled = false
        onPlaybackEnded = {}
    }

    private func restartPlaybackIfNeeded(for endedItem: AVPlayerItem) {
        guard isLoopingEnabled,
              item === endedItem,
              player?.currentItem === endedItem else {
            return
        }
        onPlaybackEnded()
        player?.seek(
            to: .zero,
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] finished in
            guard finished else { return }
            self?.player?.play()
        }
    }

    private func removeEndObserver() {
        if let endObserver {
            notificationCenter.removeObserver(endObserver)
            self.endObserver = nil
        }
    }
}

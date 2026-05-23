import Foundation

#if canImport(AVFAudio) && !os(macOS)
import AVFAudio
#endif

enum HanaPlaybackAudioSession {
    static func activateForVideoPlayback() {
#if canImport(AVFAudio) && !os(macOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true, options: [])
        } catch {
            return
        }
#endif
    }

    static func deactivateAfterPlayback() {
#if canImport(AVFAudio) && !os(macOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
#endif
    }
}

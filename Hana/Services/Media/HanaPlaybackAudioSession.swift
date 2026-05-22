import Foundation

#if canImport(AVFAudio)
import AVFAudio
#endif

enum HanaPlaybackAudioSession {
    static func activateForVideoPlayback() {
#if canImport(AVFAudio)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            return
        }
#endif
    }

    static func deactivateAfterPlayback() {
#if canImport(AVFAudio)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
#endif
    }
}

import Foundation
import MediaPlayer

final class RemoteCommandReceiver {
    private let onPlayPause: () -> Void

    init(onPlayPause: @escaping () -> Void) {
        self.onPlayPause = onPlayPause
    }

    func start() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.handle(command: "play")
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.handle(command: "pause")
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.handle(command: "togglePlayPause")
            return .success
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "MutePls",
            MPMediaItemPropertyArtist: "Microphone mute control",
            MPNowPlayingInfoPropertyPlaybackRate: 1.0
        ]
        MPNowPlayingInfoCenter.default().playbackState = .playing

        NSLog("MutePls: remote command receiver enabled")
    }

    func stop() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    private func handle(command: String) {
        NSLog("MutePls: received remote command \(command)")
        DispatchQueue.main.async { [weak self] in
            self?.onPlayPause()
        }
    }
}

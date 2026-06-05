import AVFoundation

final class AVPlayerAudioEngine: AudioEngine {
    private let player = AVPlayer()
    var onPlaybackEnded: (() -> Void)?

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didPlayToEnd(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    var currentTimeSec: Double {
        let t = player.currentTime().seconds
        return t.isFinite ? t : 0
    }

    var durationSec: Double {
        guard let d = player.currentItem?.duration.seconds, d.isFinite else { return 0 }
        return d
    }

    func load(url: URL) {
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
    }

    func play() { player.play() }
    func pause() { player.pause() }

    func seek(toSec seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    @objc private func didPlayToEnd(_ note: Notification) {
        guard (note.object as? AVPlayerItem) === player.currentItem else { return }
        onPlaybackEnded?()
    }
}

import Foundation
@testable import AudioFolderPlayer

final class FakeAudioEngine: AudioEngine {
    var currentTimeSec: Double = 0
    var durationSec: Double = 0
    var onPlaybackEnded: (() -> Void)?

    private(set) var loadedURLs: [URL] = []
    private(set) var seekedToSec: [Double] = []
    private(set) var isPlaying = false

    func load(url: URL) { loadedURLs.append(url) }
    func play() { isPlaying = true }
    func pause() { isPlaying = false }
    func seek(toSec seconds: Double) {
        currentTimeSec = seconds
        seekedToSec.append(seconds)
    }

    /// テストから再生終端イベントを発火する
    func simulatePlaybackEnded() { onPlaybackEnded?() }
}

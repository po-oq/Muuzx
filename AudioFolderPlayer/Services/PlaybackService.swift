import Foundation

final class PlaybackService {
    static let skipForwardSec: Double = 30
    static let skipBackwardSec: Double = 10

    private let engine: AudioEngine
    private(set) var items: [AudioItem]
    private(set) var currentIndex: Int?

    init(engine: AudioEngine, items: [AudioItem] = []) {
        self.engine = engine
        self.items = items
        engine.onPlaybackEnded = { [weak self] in self?.handlePlaybackEnded() }
    }

    var currentItem: AudioItem? {
        guard let i = currentIndex, items.indices.contains(i) else { return nil }
        return items[i]
    }

    func setItems(_ items: [AudioItem]) { self.items = items }

    func play(at index: Int) {
        guard items.indices.contains(index) else { return }
        currentIndex = index
        engine.load(url: items[index].localURL)
        engine.play()
    }

    func resume() { engine.play() }
    func pause() { engine.pause() }

    func skipForward() {
        let target = min(engine.currentTimeSec + Self.skipForwardSec, engine.durationSec)
        engine.seek(toSec: target)
    }

    func skipBackward() {
        let target = max(engine.currentTimeSec - Self.skipBackwardSec, 0)
        engine.seek(toSec: target)
    }

    private func handlePlaybackEnded() {
        guard let i = currentIndex else { return }
        let next = i + 1
        if items.indices.contains(next) {
            play(at: next)
        } else {
            currentIndex = nil
        }
    }
}

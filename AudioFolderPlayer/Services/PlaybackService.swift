import Foundation

enum PlaybackItemChangeReason: String, Equatable, Sendable {
    case manual
    case automatic
    case stopped
}

@MainActor
final class PlaybackService {
    static let skipForwardSec: Double = 30
    static let skipBackwardSec: Double = 10

    var onCurrentItemChanged: ((AudioItem?, PlaybackItemChangeReason) -> Void)?
    var onItemCompleted: ((AudioItem) -> Void)?

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

    var currentPositionSec: Double { engine.currentTimeSec }
    var currentDurationSec: Double { engine.durationSec }

    func setItems(_ items: [AudioItem]) {
        guard let currentItem else {
            self.items = items
            currentIndex = nil
            return
        }

        self.items = items
        if let newIndex = items.firstIndex(where: { $0.id == currentItem.id }) {
            currentIndex = newIndex
        } else {
            currentIndex = nil
            engine.pause()
            onCurrentItemChanged?(nil, .stopped)
        }
    }

    func play(at index: Int, startPositionSec: Double = 0) {
        play(at: index, startPositionSec: startPositionSec, reason: .manual)
    }

    private func play(
        at index: Int,
        startPositionSec: Double = 0,
        reason: PlaybackItemChangeReason
    ) {
        guard items.indices.contains(index) else { return }
        currentIndex = index
        engine.load(url: items[index].localURL)
        let duration = items[index].durationSec > 0 ? items[index].durationSec : engine.durationSec
        let position = max(startPositionSec, 0)
        engine.seek(toSec: duration > 0 ? min(position, duration) : position)
        engine.play()
        onCurrentItemChanged?(items[index], reason)
    }

    func resume() { engine.play() }
    func pause() { engine.pause() }

    func stop() {
        engine.pause()
        currentIndex = nil
        onCurrentItemChanged?(nil, .stopped)
    }

    func skipForward() {
        let target = min(engine.currentTimeSec + Self.skipForwardSec, engine.durationSec)
        engine.seek(toSec: target)
    }

    func skipBackward() {
        let target = max(engine.currentTimeSec - Self.skipBackwardSec, 0)
        engine.seek(toSec: target)
    }

    private func handlePlaybackEnded() {
        guard let i = currentIndex, items.indices.contains(i) else { return }
        onItemCompleted?(items[i])
        let next = i + 1
        if items.indices.contains(next) {
            play(at: next, reason: .automatic)
        } else {
            currentIndex = nil
            onCurrentItemChanged?(nil, .stopped)
        }
    }
}

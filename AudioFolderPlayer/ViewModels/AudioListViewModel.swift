import Combine
import Foundation

@MainActor
final class AudioListViewModel: ObservableObject {
    @Published private(set) var items: [AudioItem] = []
    @Published private(set) var currentItemId: String?
    @Published private(set) var isPlaying: Bool = false

    var onMetadataCancellationProcessed: (() -> Void)?

    private let library: LocalAudioLibrary
    private let playback: PlaybackService
    private let metadata: any AudioMetadataLoading
    private var metadataTask: Task<Void, Never>?
    private var playbackObservationTask: Task<Void, Never>?

    init(
        library: LocalAudioLibrary,
        playback: PlaybackService,
        metadata: any AudioMetadataLoading = AudioMetadataService()
    ) {
        self.library = library
        self.playback = playback
        self.metadata = metadata
        self.playback.onCurrentItemChanged = { [weak self] item, reason in
            self?.updateCurrentItem(item, reason: reason)
        }
        self.playback.onItemCompleted = { [weak self, weak playback] item in
            guard let self, let playback else { return }
            self.handleItemCompleted(
                item,
                positionSec: playback.currentPositionSec,
                durationSec: playback.currentDurationSec
            )
        }
    }

    func load() {
        metadataTask?.cancel()
        let previousById = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let loaded = (try? library.loadItems()) ?? []
        items = loaded.map { item in
            guard let previous = previousById[item.id] else { return item }
            var merged = item
            merged.durationSec = previous.durationSec
            merged.positionSec = previous.positionSec
            merged.status = previous.status
            merged.updatedAt = previous.updatedAt
            return merged
        }
        playback.setItems(items)
        if let currentItemId, !items.contains(where: { $0.id == currentItemId }) {
            playback.stop()
            updateCurrentItem(nil, reason: .stopped)
        }
        startMetadataLoading()
    }

    func play(_ item: AudioItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let startPosition = items[index].status == .played ? 0 : items[index].positionSec
        markInProgress(at: index, positionSec: startPosition)
        playback.setItems(items)
        playback.play(at: index, startPositionSec: startPosition)
        currentItemId = item.id
        isPlaying = true
        startObservingPlaybackIfNeeded()
    }

    func playFromBeginning(_ item: AudioItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        markInProgress(at: index, positionSec: 0)
        playback.setItems(items)
        playback.play(at: index, startPositionSec: 0)
        currentItemId = item.id
        isPlaying = true
        startObservingPlaybackIfNeeded()
    }

    func markUnplayed(_ item: AudioItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        if currentItemId == item.id {
            playback.stop()
            updateCurrentItem(nil, reason: .stopped)
        }
        items[index].positionSec = 0
        items[index].status = .unplayed
        items[index].updatedAt = Date()
        playback.setItems(items)
    }

    func togglePlayPause() {
        if isPlaying {
            playback.pause()
            refreshPlaybackState()
            isPlaying = false
            stopObservingPlayback()
        } else {
            guard currentItemId != nil else { return }
            playback.resume()
            isPlaying = true
            startObservingPlaybackIfNeeded()
        }
    }

    func skipForward() {
        playback.skipForward()
        refreshPlaybackState()
    }

    func skipBackward() {
        playback.skipBackward()
        refreshPlaybackState()
    }

    func refreshPlaybackState() {
        guard let currentItemId else { return }
        updatePlaybackState(
            for: currentItemId,
            positionSec: playback.currentPositionSec,
            durationSec: playback.currentDurationSec
        )
        playback.setItems(items)
    }

    func stopObservingPlayback() {
        playbackObservationTask?.cancel()
        playbackObservationTask = nil
    }

    func startObservingPlaybackIfNeeded() {
        guard isPlaying, currentItem != nil, playbackObservationTask == nil else { return }
        playbackObservationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                if let self {
                    self.refreshPlaybackState()
                } else {
                    return
                }
            }
        }
    }

    var currentItem: AudioItem? {
        items.first { $0.id == currentItemId }
    }

    var currentPlaybackPositionSec: Double {
        currentItemId == nil ? 0 : playback.currentPositionSec
    }

    private func updateCurrentItem(_ item: AudioItem?, reason: PlaybackItemChangeReason) {
        currentItemId = item?.id
        isPlaying = item != nil
        if let item,
           let index = items.firstIndex(where: { $0.id == item.id }),
           reason == .automatic {
            markInProgress(at: index, positionSec: 0)
            playback.setItems(items)
            startObservingPlaybackIfNeeded()
        } else if item == nil {
            stopObservingPlayback()
        } else {
            startObservingPlaybackIfNeeded()
        }
    }

    private func markInProgress(at index: Int, positionSec: Double) {
        items[index].positionSec = positionSec
        items[index].status = .inProgress
        items[index].updatedAt = Date()
    }

    private func updatePlaybackState(for id: String, positionSec: Double, durationSec: Double) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let duration = durationSec > 0 ? durationSec : items[index].durationSec
        let position = duration > 0 ? min(max(positionSec, 0), duration) : max(positionSec, 0)

        items[index].durationSec = duration
        if duration > 0, position > 0, position >= duration - 30 {
            items[index].positionSec = duration
            items[index].status = .played
        } else {
            items[index].positionSec = position
            items[index].status = position > 0 ? .inProgress : .unplayed
        }
        items[index].updatedAt = Date()
    }

    private func handleItemCompleted(
        _ item: AudioItem,
        positionSec: Double,
        durationSec: Double
    ) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let duration = durationSec > 0 ? durationSec : items[index].durationSec
        if duration > 0 {
            items[index].durationSec = duration
            items[index].positionSec = duration
        } else {
            items[index].positionSec = max(items[index].positionSec, positionSec)
        }
        items[index].status = .played
        items[index].updatedAt = Date()
        playback.setItems(items)
    }

    private func startMetadataLoading() {
        let snapshot = items
        metadataTask = Task { [weak self, metadata] in
            for item in snapshot {
                guard !Task.isCancelled else { return }

                do {
                    let duration = try await metadata.duration(for: item.localURL)
                    try Task.checkCancellation()
                    guard let self,
                          let index = self.items.firstIndex(where: { $0.id == item.id })
                    else { return }

                    self.items[index].durationSec = duration
                    self.playback.setItems(self.items)
                } catch is CancellationError {
                    self?.onMetadataCancellationProcessed?()
                    return
                } catch {
                    continue
                }
            }
        }
    }
}

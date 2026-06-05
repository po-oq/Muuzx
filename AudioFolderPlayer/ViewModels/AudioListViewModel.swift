import Combine
import Foundation

@MainActor
final class AudioListViewModel: ObservableObject {
    @Published private(set) var items: [AudioItem] = []
    @Published private(set) var currentItemId: String?
    @Published private(set) var isPlaying: Bool = false

    private let library: LocalAudioLibrary
    private let playback: PlaybackService

    init(library: LocalAudioLibrary, playback: PlaybackService) {
        self.library = library
        self.playback = playback
        self.playback.onCurrentItemChanged = { [weak self] item in
            Task { @MainActor [weak self] in
                self?.updateCurrentItem(item)
            }
        }
    }

    func load() {
        items = (try? library.loadItems()) ?? []
        playback.setItems(items)
        if let currentItemId, !items.contains(where: { $0.id == currentItemId }) {
            updateCurrentItem(nil)
        }
    }

    func play(_ item: AudioItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        playback.play(at: index)
        currentItemId = item.id
        isPlaying = true
    }

    func togglePlayPause() {
        if isPlaying {
            playback.pause()
            isPlaying = false
        } else {
            playback.resume()
            isPlaying = true
        }
    }

    func skipForward() { playback.skipForward() }
    func skipBackward() { playback.skipBackward() }

    var currentItem: AudioItem? {
        items.first { $0.id == currentItemId }
    }

    private func updateCurrentItem(_ item: AudioItem?) {
        currentItemId = item?.id
        isPlaying = item != nil
    }
}

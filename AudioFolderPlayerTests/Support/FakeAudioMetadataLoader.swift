import Foundation
@testable import AudioFolderPlayer

actor FakeAudioMetadataLoader: AudioMetadataLoading {
    private let durations: [String: Double]

    init(durations: [String: Double]) {
        self.durations = durations
    }

    func duration(for url: URL) async throws -> Double {
        guard let duration = durations[url.lastPathComponent] else {
            throw AudioMetadataError.durationUnavailable
        }
        return duration
    }
}

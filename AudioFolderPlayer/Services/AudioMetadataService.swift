import AVFoundation

protocol AudioMetadataLoading: Sendable {
    func duration(for url: URL) async throws -> Double
}

enum AudioMetadataError: Error, Equatable {
    case durationUnavailable
}

struct AudioMetadataService: AudioMetadataLoading {
    func duration(for url: URL) async throws -> Double {
        do {
            let seconds = try await AVURLAsset(url: url).load(.duration).seconds
            guard seconds.isFinite, seconds > 0 else {
                throw AudioMetadataError.durationUnavailable
            }
            return seconds
        } catch {
            throw AudioMetadataError.durationUnavailable
        }
    }
}

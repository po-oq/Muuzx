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

actor ControllableAudioMetadataLoader: AudioMetadataLoading {
    struct Request: Equatable, Sendable {
        let id: Int
        let fileName: String
    }

    private var nextID = 0
    private var requests: [Request] = []
    private var requestWaiters: [Int: [CheckedContinuation<Request, Never>]] = [:]
    private var pending: [Int: CheckedContinuation<Double, Error>] = [:]

    func duration(for url: URL) async throws -> Double {
        let request = Request(id: nextID, fileName: url.lastPathComponent)
        nextID += 1

        return try await withCheckedThrowingContinuation { continuation in
            pending[request.id] = continuation
            requests.append(request)
            requestWaiters.removeValue(forKey: requests.count - 1)?.forEach {
                $0.resume(returning: request)
            }
        }
    }

    func waitForRequest(at index: Int) async -> Request {
        if requests.indices.contains(index) {
            return requests[index]
        }

        return await withCheckedContinuation { continuation in
            requestWaiters[index, default: []].append(continuation)
        }
    }

    func complete(_ request: Request, with duration: Double) {
        pending.removeValue(forKey: request.id)?.resume(returning: duration)
    }

    func fail(_ request: Request) {
        pending.removeValue(forKey: request.id)?.resume(
            throwing: AudioMetadataError.durationUnavailable
        )
    }
}

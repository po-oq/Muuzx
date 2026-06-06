import Foundation

enum PlaybackStatus: String, Codable, Equatable, Sendable {
    case unplayed
    case inProgress
    case played
}

import Foundation

struct AudioItem: Identifiable, Codable, Equatable {
    let id: String          // fileId: normalizedName|sizeBytes
    var fileName: String
    var localURL: URL
    var fileSizeBytes: Int64
    var durationSec: Double
    var positionSec: Double
    var status: PlaybackStatus
    var updatedAt: Date
}

import Foundation

struct FolderImportSummary: Codable, Equatable, Sendable {
    var folderName: String
    var fileCount: Int
    var totalBytes: Int64
    var importedAt: Date
}

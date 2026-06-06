import Foundation

struct FolderImportProgress: Equatable, Sendable {
    var completedFiles: Int
    var totalFiles: Int
    var currentFileName: String
}

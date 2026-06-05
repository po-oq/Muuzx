import Foundation

struct FolderImportProgress: Equatable {
    var completedFiles: Int
    var totalFiles: Int
    var currentFileName: String
}

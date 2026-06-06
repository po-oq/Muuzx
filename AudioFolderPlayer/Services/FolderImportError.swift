import Foundation

enum FolderImportError: LocalizedError, Equatable {
    case noSupportedAudioFiles
    case sourceAccessDenied
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .noSupportedAudioFiles:
            return "対応音声ファイルが見つかりませんでした。"
        case .sourceAccessDenied:
            return "フォルダにアクセスできませんでした。"
        case .copyFailed(let fileName):
            return "\(fileName) のコピーに失敗しました。"
        }
    }
}

import Foundation

enum AppDirectories {
    static let appFolderName = "AudioFolderPlayer"

    static func appSupportRoot(_ fm: FileManager = .default) throws -> URL {
        let base = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let url = base.appendingPathComponent(appFolderName, isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func audioDirectory(_ fm: FileManager = .default) throws -> URL {
        let url = try appSupportRoot(fm).appendingPathComponent("audio", isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func stateDirectory(_ fm: FileManager = .default) throws -> URL {
        let url = try appSupportRoot(fm).appendingPathComponent("state", isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func folderImportSummaryFile(_ fm: FileManager = .default) throws -> URL {
        try stateDirectory(fm).appendingPathComponent("folder-import-summary.json")
    }

    static func folderBookmarkFile(_ fm: FileManager = .default) throws -> URL {
        try stateDirectory(fm).appendingPathComponent("folder-bookmark.data")
    }
}

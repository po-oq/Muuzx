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
        return base.appendingPathComponent(appFolderName, isDirectory: true)
    }

    static func audioDirectory(_ fm: FileManager = .default) throws -> URL {
        let url = try appSupportRoot(fm).appendingPathComponent("audio", isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

import Foundation

struct LocalAudioLibrary {
    static let supportedExtensions: Set<String> = ["mp3", "m4a"]

    let directory: URL
    private let fileManager: FileManager

    init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    func loadItems() throws -> [AudioItem] {
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        let items = try urls
            .filter { Self.supportedExtensions.contains($0.pathExtension.lowercased()) }
            .map { url -> AudioItem in
                let size = Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
                let name = url.lastPathComponent
                return AudioItem(
                    id: FileIdentifier.make(fileName: name, sizeBytes: size),
                    fileName: name,
                    localURL: url,
                    fileSizeBytes: size,
                    durationSec: 0,
                    positionSec: 0,
                    status: .unplayed,
                    updatedAt: Date()
                )
            }

        return items.sorted {
            $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
        }
    }
}

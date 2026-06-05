import Foundation

protocol FolderImporting {
    func importFolder(
        _ sourceDirectory: URL,
        mode: ImportMode,
        progress: (FolderImportProgress) -> Void
    ) throws -> FolderImportResult
}

struct FolderImportResult: Equatable {
    var items: [AudioItem]
    var summary: FolderImportSummary
}

struct FolderImportService: FolderImporting {
    let destinationDirectory: URL
    private let fileManager: FileManager

    init(destinationDirectory: URL, fileManager: FileManager = .default) {
        self.destinationDirectory = destinationDirectory
        self.fileManager = fileManager
    }

    func importFolder(
        _ sourceDirectory: URL,
        mode: ImportMode,
        progress: (FolderImportProgress) -> Void = { _ in }
    ) throws -> FolderImportResult {
        let accessed = sourceDirectory.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                sourceDirectory.stopAccessingSecurityScopedResource()
            }
        }

        guard fileManager.fileExists(atPath: sourceDirectory.path) else {
            throw FolderImportError.sourceAccessDenied
        }

        let sourceFiles = try supportedFiles(in: sourceDirectory)
        guard !sourceFiles.isEmpty else {
            throw FolderImportError.noSupportedAudioFiles
        }

        if sameDirectory(sourceDirectory, destinationDirectory) {
            return try importedResult(
                sourceDirectory: sourceDirectory,
                sourceFiles: sourceFiles,
                progress: progress
            )
        }

        try prepareDestination(for: mode)

        var completed = 0
        for sourceURL in sourceFiles {
            let destinationURL = destinationDirectory.appendingPathComponent(sourceURL.lastPathComponent)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            do {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            } catch {
                throw FolderImportError.copyFailed(sourceURL.lastPathComponent)
            }
            completed += 1
            progress(FolderImportProgress(
                completedFiles: completed,
                totalFiles: sourceFiles.count,
                currentFileName: sourceURL.lastPathComponent
            ))
        }

        return try importedResult(
            sourceDirectory: sourceDirectory,
            sourceFiles: sourceFiles,
            progress: { _ in }
        )
    }

    private func importedResult(
        sourceDirectory: URL,
        sourceFiles: [URL],
        progress: (FolderImportProgress) -> Void
    ) throws -> FolderImportResult {
        for (index, sourceURL) in sourceFiles.enumerated() {
            progress(FolderImportProgress(
                completedFiles: index + 1,
                totalFiles: sourceFiles.count,
                currentFileName: sourceURL.lastPathComponent
            ))
        }

        let items = try LocalAudioLibrary(directory: destinationDirectory, fileManager: fileManager).loadItems()
        let importedNames = Set(sourceFiles.map(\.lastPathComponent))
        let importedItems = items.filter { importedNames.contains($0.fileName) }
        let summary = FolderImportSummary(
            folderName: sourceDirectory.standardizedFileURL.lastPathComponent,
            fileCount: importedItems.count,
            totalBytes: importedItems.reduce(Int64(0)) { $0 + $1.fileSizeBytes },
            importedAt: Date()
        )
        return FolderImportResult(items: importedItems, summary: summary)
    }

    private func supportedFiles(in directory: URL) throws -> [URL] {
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        return try urls
            .filter { LocalAudioLibrary.supportedExtensions.contains($0.pathExtension.lowercased()) }
            .filter { url in
                let values = try url.resourceValues(forKeys: [.isRegularFileKey])
                return values.isRegularFile == true
            }
            .sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
    }

    private func sameDirectory(_ lhs: URL, _ rhs: URL) -> Bool {
        canonicalPath(for: lhs) == canonicalPath(for: rhs)
    }

    private func canonicalPath(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func prepareDestination(for mode: ImportMode) throws {
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        switch mode {
        case .replaceAll:
            let existing = try fileManager.contentsOfDirectory(
                at: destinationDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for url in existing {
                try fileManager.removeItem(at: url)
            }
        case .mergeOverwrite:
            break
        }
    }
}

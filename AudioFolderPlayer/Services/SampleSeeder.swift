import Foundation

/// 同梱されたサンプル音声を、audio ディレクトリが空のときだけコピーする（Step1 の動作確認用）。
struct SampleSeeder {
    let bundle: Bundle
    let destination: URL
    private let fileManager: FileManager

    init(bundle: Bundle = .main, destination: URL, fileManager: FileManager = .default) {
        self.bundle = bundle
        self.destination = destination
        self.fileManager = fileManager
    }

    func seedIfEmpty() throws {
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let existing = try fileManager.contentsOfDirectory(atPath: destination.path)
        guard existing.isEmpty else { return }

        for ext in ["mp3", "m4a"] {
            for src in bundle.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? [] {
                let dest = destination.appendingPathComponent(src.lastPathComponent)
                try? fileManager.copyItem(at: src, to: dest)
            }
        }
    }
}

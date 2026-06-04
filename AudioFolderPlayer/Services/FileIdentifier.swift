import Foundation

enum FileIdentifier {
    /// fileId = 正規化ファイル名 + "|" + サイズ（byte）
    static func make(fileName: String, sizeBytes: Int64) -> String {
        "\(normalize(fileName))|\(sizeBytes)"
    }

    /// 前後空白除去 → NFC正規化 → 小文字化。端末間で完全一致させるための正規化。
    static func normalize(_ fileName: String) -> String {
        fileName
            .trimmingCharacters(in: .whitespaces)
            .precomposedStringWithCanonicalMapping
            .lowercased()
    }
}

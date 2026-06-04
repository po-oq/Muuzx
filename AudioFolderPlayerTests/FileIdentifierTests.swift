import XCTest
@testable import AudioFolderPlayer

final class FileIdentifierTests: XCTestCase {
    func test_make_combinesNormalizedNameAndSize() {
        let id = FileIdentifier.make(fileName: "AWS設計入門 02.mp3", sizeBytes: 73_400_320)
        XCTAssertEqual(id, "aws設計入門 02.mp3|73400320")
    }

    func test_normalize_trimsWhitespace() {
        XCTAssertEqual(FileIdentifier.normalize("  track.mp3  "), "track.mp3")
    }

    func test_normalize_isCaseInsensitive() {
        XCTAssertEqual(FileIdentifier.normalize("Track.MP3"), "track.mp3")
    }

    func test_normalize_usesNFC() {
        // "が" を NFD（か + 濁点）で構成した文字列が NFC へ正規化されること
        let nfd = "\u{304B}\u{3099}.mp3"           // か + 結合濁点
        let nfc = "\u{304C}.mp3"                    // が（合成済み）
        XCTAssertEqual(FileIdentifier.normalize(nfd), nfc)
    }
}

import XCTest
@testable import AudioFolderPlayer

final class AudioFolderPlayerTests: XCTestCase {
    func testBundleLoads() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.pooq.AudioFolderPlayer")
    }
}

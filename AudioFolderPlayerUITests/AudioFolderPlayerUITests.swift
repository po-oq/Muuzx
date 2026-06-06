import XCTest

final class AudioFolderPlayerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFolderScreenCanOpenAudioListAndUseMiniPlayerControls() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--reset-ui-test-audio")
        app.launch()

        XCTAssertTrue(app.staticTexts["folder-summary-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["choose-folder-button"].exists)

        let openListButton = app.buttons["open-audio-list-button"]
        XCTAssertTrue(openListButton.waitForExistence(timeout: 5))
        openListButton.tap()

        let firstSample = app.buttons["audio-row-sample-01.mp3"]
        let secondSample = app.buttons["audio-row-sample-02.mp3"]
        XCTAssertTrue(firstSample.waitForExistence(timeout: 5))
        XCTAssertTrue(secondSample.exists)

        firstSample.tap()

        XCTAssertTrue(app.images["current-item-speaker"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["mini-player-title"].label, "sample-01.mp3")

        let playPauseButton = app.buttons["play-pause-button"]
        XCTAssertTrue(playPauseButton.exists)
        playPauseButton.tap()
        playPauseButton.tap()

        app.buttons["skip-backward-button"].tap()
        app.buttons["skip-forward-button"].tap()
    }
}

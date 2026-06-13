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
        XCTAssertTrue(secondSample.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["audio-status-sample-01.mp3"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.progressIndicators["mini-player-progress"].waitForExistence(timeout: 2))

        firstSample.press(forDuration: 1.2)
        let playFromBeginningButton = app.buttons["先頭から再生"]
        let markUnplayedButton = app.buttons["未再生に戻す"]
        XCTAssertTrue(playFromBeginningButton.waitForExistence(timeout: 2))
        XCTAssertTrue(markUnplayedButton.waitForExistence(timeout: 2))
        app.tap()
        XCTAssertTrue(playFromBeginningButton.waitForNonExistence(timeout: 2))

        firstSample.tap()

        XCTAssertTrue(app.images["current-item-speaker"].waitForExistence(timeout: 2))
        let firstSampleStatus = app.staticTexts["audio-status-sample-01.mp3"]
        let playingStatus = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "再生中"),
            object: firstSampleStatus
        )
        XCTAssertTrue(
            XCTWaiter.wait(for: [playingStatus], timeout: 2) == .completed
        )
        let miniPlayerTitle = app.staticTexts["mini-player-title"]
        let expectedMiniPlayerTitle = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "sample-01.mp3"),
            object: miniPlayerTitle
        )
        XCTAssertTrue(
            XCTWaiter.wait(for: [expectedMiniPlayerTitle], timeout: 2) == .completed
        )

        let playPauseButton = app.buttons["play-pause-button"]
        XCTAssertTrue(playPauseButton.waitForExistence(timeout: 2))
        playPauseButton.tap()
        playPauseButton.tap()

        app.buttons["skip-backward-button"].tap()
        app.buttons["skip-forward-button"].tap()
    }
}

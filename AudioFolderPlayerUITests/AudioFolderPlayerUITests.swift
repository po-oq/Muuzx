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
        let firstSampleStatus = app.staticTexts["audio-status-sample-01.mp3"]
        XCTAssertTrue(firstSample.waitForExistence(timeout: 5))
        XCTAssertTrue(secondSample.waitForExistence(timeout: 2))
        XCTAssertTrue(
            waitForLabel(firstSampleStatus, toEqual: "未再生"),
            "Expected sample-01 badge to initially be 未再生, but was \(firstSampleStatus.label)"
        )
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
        XCTAssertTrue(
            waitForLabel(firstSampleStatus, toEqual: "再生中"),
            "Expected sample-01 badge to become 再生中, but was \(firstSampleStatus.label)"
        )
        let miniPlayerTitle = app.staticTexts["mini-player-title"]
        XCTAssertTrue(
            waitForLabel(miniPlayerTitle, toEqual: "sample-01.mp3"),
            "Expected mini-player title to be sample-01.mp3, but was \(miniPlayerTitle.label)"
        )

        let playPauseButton = app.buttons["play-pause-button"]
        XCTAssertTrue(playPauseButton.waitForExistence(timeout: 2))
        playPauseButton.tap()
        XCTAssertTrue(
            waitForValue(playPauseButton, toEqual: "一時停止中"),
            "Expected play/pause control to expose 一時停止中 after pausing, but was \(String(describing: playPauseButton.value))"
        )
        playPauseButton.tap()
        XCTAssertTrue(
            waitForValue(playPauseButton, toEqual: "再生中"),
            "Expected play/pause control to expose 再生中 after resuming, but was \(String(describing: playPauseButton.value))"
        )
        playPauseButton.tap()
        XCTAssertTrue(
            waitForValue(playPauseButton, toEqual: "一時停止中"),
            "Expected play/pause control to expose 一時停止中 before skipping, but was \(String(describing: playPauseButton.value))"
        )

        let currentTime = app.staticTexts["mini-player-current-time"]
        XCTAssertTrue(
            currentTime.waitForExistence(timeout: 2),
            "Expected mini-player current time to exist after pausing"
        )
        let positionBeforeSkip = try XCTUnwrap(
            displayedSeconds(currentTime.label),
            "Expected parseable current time before skip, but was \(currentTime.label)"
        )
        let skipBackwardButton = app.buttons["skip-backward-button"]
        let skipForwardButton = app.buttons["skip-forward-button"]
        XCTAssertTrue(
            skipBackwardButton.waitForExistence(timeout: 2),
            "Expected skip-backward control to exist"
        )
        XCTAssertTrue(
            skipForwardButton.waitForExistence(timeout: 2),
            "Expected skip-forward control to exist"
        )

        skipBackwardButton.tap()
        XCTAssertTrue(
            waitForDisplayedSeconds(currentTime) { $0 < positionBeforeSkip },
            "Expected skip-backward to reduce current time below \(positionBeforeSkip)s, but was \(currentTime.label)"
        )
        let positionAfterBackward = try XCTUnwrap(
            displayedSeconds(currentTime.label),
            "Expected parseable current time after skip-backward, but was \(currentTime.label)"
        )
        skipForwardButton.tap()
        XCTAssertTrue(
            waitForDisplayedSeconds(currentTime) { $0 > positionAfterBackward },
            "Expected skip-forward to increase current time beyond \(positionAfterBackward)s or reach its duration clamp, but was \(currentTime.label)"
        )
    }

    private func waitForLabel(
        _ element: XCUIElement,
        toEqual expectedLabel: String,
        timeout: TimeInterval = 2
    ) -> Bool {
        wait(
            for: element,
            predicate: NSPredicate(format: "label == %@", expectedLabel),
            timeout: timeout
        )
    }

    private func waitForValue(
        _ element: XCUIElement,
        toEqual expectedValue: String,
        timeout: TimeInterval = 2
    ) -> Bool {
        wait(
            for: element,
            predicate: NSPredicate(format: "value == %@", expectedValue),
            timeout: timeout
        )
    }

    private func waitForDisplayedSeconds(
        _ element: XCUIElement,
        satisfies condition: @escaping (Int) -> Bool,
        timeout: TimeInterval = 2
    ) -> Bool {
        wait(
            for: element,
            predicate: NSPredicate { object, _ in
                guard let element = object as? XCUIElement,
                      let seconds = self.displayedSeconds(element.label)
                else { return false }
                return condition(seconds)
            },
            timeout: timeout
        )
    }

    private func wait(
        for element: XCUIElement,
        predicate: NSPredicate,
        timeout: TimeInterval
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func displayedSeconds(_ value: String) -> Int? {
        let components = value.split(separator: ":").compactMap { Int($0) }
        guard components.count == 2 else { return nil }
        return components[0] * 60 + components[1]
    }
}

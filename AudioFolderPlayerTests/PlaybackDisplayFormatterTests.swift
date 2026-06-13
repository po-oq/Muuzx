import XCTest
@testable import AudioFolderPlayer

final class PlaybackDisplayFormatterTests: XCTestCase {
    func test_time_formatsMinutesAndSeconds() {
        XCTAssertEqual(PlaybackDisplayFormatter.time(72), "1:12")
    }

    func test_time_formatsHours() {
        XCTAssertEqual(PlaybackDisplayFormatter.time(4360), "1:12:40")
    }

    func test_timeFormatsHoursBeyondInt32WithoutWrappingNegative() {
        let seconds = Double(Int(Int32.max) + 1) * 3600

        XCTAssertEqual(PlaybackDisplayFormatter.time(seconds), "2147483648:00:00")
    }

    func test_timeCapsFiniteValuesBeyondIntRangeAtIntMaxSeconds() {
        XCTAssertEqual(
            PlaybackDisplayFormatter.time(.greatestFiniteMagnitude),
            "2562047788015215:30:07"
        )
    }

    func test_timeClampsInvalidValuesToZero() {
        XCTAssertEqual(PlaybackDisplayFormatter.time(-1), "0:00")
        XCTAssertEqual(PlaybackDisplayFormatter.time(.nan), "0:00")
        XCTAssertEqual(PlaybackDisplayFormatter.time(.infinity), "0:00")
        XCTAssertEqual(PlaybackDisplayFormatter.time(-.infinity), "0:00")
    }

    func test_progressClampsBetweenZeroAndOne() {
        XCTAssertEqual(PlaybackDisplayFormatter.progress(position: 150, duration: 100), 1)
        XCTAssertEqual(PlaybackDisplayFormatter.progress(position: -1, duration: 100), 0)
    }

    func test_progressReturnsZeroForUnknownOrInvalidDuration() {
        XCTAssertEqual(PlaybackDisplayFormatter.progress(position: 50, duration: 0), 0)
        XCTAssertEqual(PlaybackDisplayFormatter.progress(position: 50, duration: -1), 0)
        XCTAssertEqual(PlaybackDisplayFormatter.progress(position: 50, duration: .nan), 0)
        XCTAssertEqual(PlaybackDisplayFormatter.progress(position: 50, duration: .infinity), 0)
    }

    func test_progressClampsInvalidPositionToZero() {
        XCTAssertEqual(PlaybackDisplayFormatter.progress(position: .nan, duration: 100), 0)
        XCTAssertEqual(PlaybackDisplayFormatter.progress(position: .infinity, duration: 100), 0)
        XCTAssertEqual(PlaybackDisplayFormatter.progress(position: -.infinity, duration: 100), 0)
    }

    func test_subtitleForUnplayed() {
        XCTAssertEqual(
            PlaybackDisplayFormatter.subtitle(status: .unplayed, position: 0, duration: 125),
            "未再生・2:05"
        )
        XCTAssertEqual(
            PlaybackDisplayFormatter.subtitle(status: .unplayed, position: 0, duration: 0),
            "未再生"
        )
    }

    func test_subtitleForInProgress() {
        XCTAssertEqual(
            PlaybackDisplayFormatter.subtitle(status: .inProgress, position: 72, duration: 260),
            "途中・1:12 / 4:20"
        )
        XCTAssertEqual(
            PlaybackDisplayFormatter.subtitle(status: .inProgress, position: 72, duration: 0),
            "途中・1:12"
        )
    }

    func test_subtitleForPlayed() {
        XCTAssertEqual(
            PlaybackDisplayFormatter.subtitle(status: .played, position: 125, duration: 125),
            "完了・2:05"
        )
        XCTAssertEqual(
            PlaybackDisplayFormatter.subtitle(status: .played, position: 0, duration: 0),
            "完了"
        )
    }

    func test_subtitleTreatsInvalidDurationAsUnknown() {
        XCTAssertEqual(
            PlaybackDisplayFormatter.subtitle(status: .unplayed, position: 0, duration: .nan),
            "未再生"
        )
        XCTAssertEqual(
            PlaybackDisplayFormatter.subtitle(status: .played, position: 0, duration: .infinity),
            "完了"
        )
    }
}

import XCTest
@testable import EchoOne

final class MeetingWindowHeuristicsTests: XCTestCase {
    func testBestAutoUpdateTitleIgnoresTitlesFromDifferentAppBundle() {
        XCTAssertNil(
            MeetingWindowHeuristics.bestAutoUpdateTitle(
                in: ["Echo One Settings"],
                appName: "Zoom",
                observedBundleIdentifier: "com.goelstudio.echoone",
                monitoredBundleIdentifier: "us.zoom.xos"
            )
        )
    }

    func testBestMeetingTitlePrefersNamedZoomMeetingOverUtilityWindows() {
        XCTAssertEqual(
            MeetingWindowHeuristics.bestMeetingTitle(
                in: ["Settings", "Zoom Meeting", "Matt's Weekly Standup - Zoom"],
                appName: "Zoom"
            ),
            "Matt's Weekly Standup"
        )
    }

    func testZoomMeetingStillAppearsActiveForGenericMeetingWindow() {
        XCTAssertTrue(
            MeetingWindowHeuristics.indicatesActiveMeeting(
                in: ["Zoom Meeting", "Settings"],
                appName: "Zoom"
            )
        )
    }

    func testZoomMeetingAppearsEndedWhenOnlyUtilityWindowsRemain() {
        XCTAssertFalse(
            MeetingWindowHeuristics.indicatesActiveMeeting(
                in: ["Settings", "Home", "Zoom Workplace"],
                appName: "Zoom"
            )
        )
    }
}

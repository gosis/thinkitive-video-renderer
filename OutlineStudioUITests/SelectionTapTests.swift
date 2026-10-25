//
//  SelectionTapTests.swift
//  OutlineStudioUITests
//

import XCTest

/// One tap should switch between watching (nothing selected) and editing a layer,
/// including the slight wobble of a real finger.
final class SelectionTapTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-useSampleClip"]
        app.launch()
        XCTAssertTrue(app.otherElements["Playhead"].waitForExistence(timeout: 20))
    }

    /// Shown in place of the inspector while nothing is selected.
    private var hint: XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Select a text'")).firstMatch
    }
    private var caption: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Caption '")).element(boundBy: 1)
    }
    private var preview: XCUIElement { app.otherElements["videoPreview"] }

    /// A tap that drifts a few points, like a finger does.
    private func fingerTap(_ point: XCUICoordinate) {
        point.press(forDuration: 0.05, thenDragTo: point.withOffset(CGVector(dx: 5, dy: 2)))
    }

    private func waitUntilEditing(_ message: String) {
        let deadline = Date().addingTimeInterval(1)
        while hint.exists && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertFalse(hint.exists, message)
    }

    private func waitUntilWatching(_ message: String) {
        XCTAssertTrue(hint.waitForExistence(timeout: 1), message)
    }

    func testFingerTapOnATimelineLayerOpensEditing() {
        XCTAssertTrue(hint.exists, "Should start with nothing selected")
        fingerTap(caption.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        waitUntilEditing("A finger tap on a caption didn't open editing")
    }

    func testFingerTapOnTheVideoLeavesEditing() {
        caption.tap()
        waitUntilEditing("Caption tap didn't select")
        fingerTap(preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)))
        waitUntilWatching("A finger tap on the video didn't leave editing")
    }

    func testTapBesideTheVideoLeavesEditing() {
        caption.tap()
        waitUntilEditing("Caption tap didn't select")
        // The dark letterbox to the left of the portrait video
        let stage = app.otherElements["stage"]
        stage.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.5)).tap()
        waitUntilWatching("A tap beside the video didn't leave editing")
    }

    /// The ruler spans the whole timeline; a point `fraction` of the way along it,
    /// `down` points below its centre (the caption lane sits just under the ruler).
    private func timelinePoint(_ fraction: CGFloat, down: CGFloat = 0) -> XCUICoordinate {
        app.otherElements["Playhead"].coordinate(withNormalizedOffset: CGVector(dx: fraction, dy: 0.5))
            .withOffset(CGVector(dx: 0, dy: down))
    }

    func testTapsAcrossTheCaptionLaneOpenEditing() {
        // Captions fill most of the clip, so these all land on a caption block
        for fraction in [0.3, 0.55, 0.8] as [CGFloat] {
            app.otherElements["stage"].coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.5)).tap()
            waitUntilWatching("Couldn't deselect before tapping at \(fraction)")
            fingerTap(timelinePoint(fraction, down: 32))
            waitUntilEditing("A tap at \(Int(fraction * 100))% along the caption lane didn't open editing")
        }
    }

    func testTapOnTheRulerSeeks() {
        let playhead = app.otherElements["Playhead"]
        let before = playhead.value as? String
        timelinePoint(0.7).tap()
        XCTAssertNotEqual(playhead.value as? String, before, "Tapping the time ruler didn't move the playhead")
    }

    func testTappingBackAndForth() {
        for round in 1...3 {
            fingerTap(caption.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
            waitUntilEditing("Round \(round): caption tap didn't select")
            fingerTap(preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)))
            waitUntilWatching("Round \(round): video tap didn't deselect")
        }
    }
}

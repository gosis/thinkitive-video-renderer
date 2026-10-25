//
//  EditorInteractionTests.swift
//  OutlineStudioUITests
//

import XCTest

final class EditorInteractionTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-useSampleClip"]
        app.launch()
        XCTAssertTrue(playhead.waitForExistence(timeout: 20), "Editor did not open with the sample clip")
    }

    private var playhead: XCUIElement { app.otherElements["Playhead"] }
    private var textField: XCUIElement { app.descendants(matching: .any)["overlayText"].firstMatch }
    /// The first caption on the timeline; the sample opens with only its captions.
    private var clip: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Caption '")).firstMatch
    }

    private var playheadTime: String { playhead.value as? String ?? "" }

    /// Drags horizontally across `element` between two fractions of its width.
    private func drag(_ element: XCUIElement, from start: CGFloat, to end: CGFloat) {
        let from = element.coordinate(withNormalizedOffset: CGVector(dx: start, dy: 0.5))
        let to = element.coordinate(withNormalizedOffset: CGVector(dx: end, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: to)
    }

    /// Drags sideways from the middle of `element` by `points`, past its own edges.
    private func drag(_ element: XCUIElement, by points: CGFloat) {
        let from = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: points, dy: 0)))
    }

    func testDraggingOnTheClipLaneMovesThePlayhead() {
        let before = playheadTime
        drag(clip, by: 160)
        XCTAssertNotEqual(playheadTime, before, "Dragging over a timeline lane should scrub")
    }

    func testSwipeDownDismissesKeyboardAndPlayheadStillScrubs() {
        // Select a caption so the inspector shows its text field, and let it finish sliding in
        clip.tap()
        XCTAssertTrue(textField.waitForExistence(timeout: 3), "Inspector didn't open")
        let tappable = NSPredicate(format: "hittable == true")
        expectation(for: tappable, evaluatedWith: textField)
        waitForExpectations(timeout: 3)
        Thread.sleep(forTimeInterval: 0.4)
        textField.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Keyboard did not appear")
        save(XCUIScreen.main.screenshot(), as: "keyboard-up")

        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        top.press(forDuration: 0.05, thenDragTo: bottom)

        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.keyboards.firstMatch)
        waitForExpectations(timeout: 5)
        save(XCUIScreen.main.screenshot(), as: "keyboard-dismissed")

        // The editor should settle back with the preview fully below the toolbar
        let export = app.buttons["Export"]
        let preview = app.otherElements["videoPreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 2))
        let settled = NSPredicate { _, _ in preview.frame.minY >= export.frame.maxY }
        expectation(for: settled, evaluatedWith: nil)
        waitForExpectations(timeout: 3)

        let before = playheadTime
        drag(playhead, from: 0.1, to: 0.8)
        XCTAssertNotEqual(playheadTime, before, "Ruler should scrub after the keyboard closes")

        let afterRuler = playheadTime
        drag(clip, by: 140)
        XCTAssertNotEqual(playheadTime, afterRuler, "Timeline lanes should scrub after the keyboard closes")
    }

    func testPointerMenuDefaultsToOffAndCanBeChanged() {
        // The sample's own title uses a pencil, so check a newly added text
        app.buttons["Add text"].tap()
        app.buttons["Style"].tap()
        let menu = app.buttons["pointerMenu"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "Pointer menu missing from the Style tab")
        // The chosen option shows as the menu's value or as text inside it, depending on the OS
        let selection = {
            ([menu.label, menu.value as? String ?? ""] + menu.staticTexts.allElementsBoundByIndex.map(\.label))
                .joined(separator: " ")
        }
        XCTAssertTrue(selection().contains("Off"), "Pointer should default to Off, was \(selection())")

        menu.tap()
        app.buttons["Spark"].tap()
        XCTAssertTrue(selection().contains("Spark"), "Choosing Spark didn't stick, was \(selection())")
    }

    func testFontPickerIsGroupedAndHasSubtitleFonts() {
        clip.tap()
        let subtitles = app.buttons["Subtitles fonts"]
        XCTAssertTrue(subtitles.waitForExistence(timeout: 3), "Font groups missing from the Text tab")
        save(XCUIScreen.main.screenshot(), as: "font-picker-initial")
        subtitles.tap()

        // The bundled faces only appear if they were registered at launch
        for font in ["TikTokSans16pt-Bold", "Montserrat-ExtraBold", "HelveticaNeue-Bold",
                     "Arial-BoldMT", "Verdana-Bold", "AtkinsonHyperlegible-Bold"] {
            XCTAssertTrue(app.buttons["font-\(font)"].waitForExistence(timeout: 2), "\(font) missing from Subtitles")
        }
        let tiktok = app.buttons["font-TikTokSans16pt-Bold"]
        tiktok.tap()
        XCTAssertTrue(tiktok.isSelected, "Choosing TikTok Sans didn't apply")
        Thread.sleep(forTimeInterval: 0.5)
        save(XCUIScreen.main.screenshot(), as: "font-picker-subtitles")
    }

    private func save(_ screenshot: XCUIScreenshot, as name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

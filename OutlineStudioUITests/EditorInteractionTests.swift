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
    private var clip: XCUIElement { app.buttons["Text Hello"].firstMatch }

    private var playheadTime: String { playhead.value as? String ?? "" }

    /// Drags horizontally across `element` between two fractions of its width.
    private func drag(_ element: XCUIElement, from start: CGFloat, to end: CGFloat) {
        let from = element.coordinate(withNormalizedOffset: CGVector(dx: start, dy: 0.5))
        let to = element.coordinate(withNormalizedOffset: CGVector(dx: end, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: to)
    }

    func testDraggingOnTheClipLaneMovesThePlayhead() {
        let before = playheadTime
        drag(clip, from: 0.1, to: 0.6)
        XCTAssertNotEqual(playheadTime, before, "Dragging over a clip lane should scrub")
    }

    func testSwipeDownDismissesKeyboardAndPlayheadStillScrubs() {
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
        drag(clip, from: 0.7, to: 0.2)
        XCTAssertNotEqual(playheadTime, afterRuler, "Clip lane should scrub after the keyboard closes")
    }

    func testPointerMenuDefaultsToOffAndCanBeChanged() {
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

    private func save(_ screenshot: XCUIScreenshot, as name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

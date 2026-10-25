//
//  LayerDeletionTests.swift
//  OutlineStudioUITests
//

import XCTest

/// Deleting layers used to crash: a view held a layer by its position in the list
/// and read past the end once the list shrank.
final class LayerDeletionTests: XCTestCase {
    func testAddingAndDeletingManyLayersDoesNotCrash() {
        let app = XCUIApplication()
        app.launchArguments = ["-useSampleClip"]
        app.launch()
        XCTAssertTrue(app.otherElements["Playhead"].waitForExistence(timeout: 20))

        let add = app.buttons["Add text"]
        let delete = app.buttons["Delete text"]
        for round in 1...3 {
            for _ in 1...4 { add.tap() }
            // Each delete selects the next layer, so keep deleting until none are left
            for _ in 1...4 {
                XCTAssertTrue(delete.waitForExistence(timeout: 2), "Round \(round): delete button missing")
                delete.tap()
            }
            XCTAssertEqual(app.state, .runningForeground, "App crashed in round \(round)")
        }
        // Still alive and editable afterwards
        add.tap()
        let textField = app.descendants(matching: .any)["overlayText"].firstMatch
        XCTAssertTrue(textField.waitForExistence(timeout: 3), "Inspector didn't open after the deletes")
    }
}

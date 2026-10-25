//
//  AutoCaptionTests.swift
//  OutlineStudioUITests
//

import XCTest

final class AutoCaptionTests: XCTestCase {
    func testAutoCaptionsAddCaptionLayer() throws {
        let app = XCUIApplication()
        // The bundled sample is an astronaut talking to camera
        app.launchArguments = ["-useSampleClip"]
        app.launch()

        let playhead = app.otherElements["Playhead"]
        XCTAssertTrue(playhead.waitForExistence(timeout: 20), "Editor did not open the sample clip")

        // Speech permission may be requested the first time
        addUIInterruptionMonitor(withDescription: "Speech permission") { alert in
            guard alert.label.localizedCaseInsensitiveContains("speech"),
                  alert.buttons["Allow"].exists else { return false }
            alert.buttons["Allow"].tap()
            return true
        }

        // The sample opens already captioned; regenerating must transcribe it again
        app.buttons["Auto captions"].tap()
        // Short clips can finish before the "Listening" card is ever seen, so accept
        // either the card or the result: regenerating selects the first caption
        let listening = app.staticTexts["Listening for speech…"]
        let editing = app.buttons["Timing"]
        let started = NSPredicate { _, _ in listening.exists || editing.exists }
        expectation(for: started, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        // Interruption monitors only run on the next interaction; tap somewhere inert
        app.staticTexts["Inkcap"].firstMatch.tap()

        let finished = NSPredicate(format: "exists == false")
        expectation(for: finished, evaluatedWith: listening)
        waitForExpectations(timeout: 180)

        let failure = app.alerts["Something went wrong"]
        if failure.exists {
            XCTFail("Captioning failed: \(failure.staticTexts.allElementsBoundByIndex.map(\.label))")
        }
        let caption = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Caption '")).firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: 5), "No captions after regenerating")

        let captions = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Caption '"))
        let labels = captions.allElementsBoundByIndex.map(\.label)
        print("CAPTIONS:", labels)
        let attachment = XCTAttachment(string: labels.joined(separator: "\n"))
        attachment.name = "caption-text"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Capture the writing at a few points in time
        for fraction in [0.15, 0.3, 0.5, 0.75] {
            playhead.coordinate(withNormalizedOffset: CGVector(dx: fraction, dy: 0.5)).tap()
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "captions-\(Int(fraction * 100))"
            shot.lifetime = .keepAlways
            add(shot)
        }
    }
}

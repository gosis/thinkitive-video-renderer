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

        app.buttons["Auto captions"].tap()
        // Interruption monitors only run on the next interaction; tap somewhere inert
        sleep(3)
        app.staticTexts["Outline"].firstMatch.tap()

        let failure = app.alerts["Something went wrong"]

        // The first run may download the speech model
        let caption = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Caption '")).firstMatch
        let appeared = caption.waitForExistence(timeout: 180)
        if failure.exists {
            XCTFail("Captioning failed: \(failure.staticTexts.allElementsBoundByIndex.map(\.label))")
        }
        XCTAssertTrue(appeared, "No captions were created")

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

import XCTest

final class SmokeTests: XCTestCase {
    @MainActor
    func testSeedReviewImportRepeatAndExport() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.buttons["Seed demo data"].tap()
        XCTAssertTrue(app.staticTexts["Demo data loaded."].waitForExistence(timeout: 10))
        app.tabBars.buttons["Review"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Blue Bottle Oakland")).firstMatch.tap()
        let dining = app.buttons["dining"]
        for _ in 0..<5 where !dining.isHittable { app.swipeUp() }
        dining.tap()
        XCTAssertTrue(app.staticTexts["reviewStatus"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.staticTexts["Next best actions"].exists)
        app.tabBars.buttons["Import"].tap()
        app.buttons["Load sample JSON"].tap()
        app.buttons["Import pasted JSON"].tap()
        app.swipeUp()
        let summary = app.staticTexts["importSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        XCTAssertEqual(summary.label, "1 imported · 0 already imported · 0 failed")
        app.swipeDown()
        app.buttons["Load sample JSON"].tap()
        app.buttons["Import pasted JSON"].tap()
        app.swipeUp()
        let repeated = NSPredicate(format: "label == %@", "0 imported · 1 already imported · 0 failed")
        expectation(for: repeated, evaluatedWith: summary)
        waitForExpectations(timeout: 15)
        app.tabBars.buttons["Settings"].tap()
        app.buttons["Export JSON backup"].tap()
        XCTAssertTrue(app.staticTexts["Backup ready to share."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Share export file"].exists)
    }
}

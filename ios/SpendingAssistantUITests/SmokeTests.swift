import XCTest

final class SmokeTests: XCTestCase {
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
    }

    @MainActor
    func testScreenshotImportAsksForYearAndAccount() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-screenshot-details"]
        app.launch()
        let year = app.buttons["statementYearPicker"]
        XCTAssertTrue(year.waitForExistence(timeout: 15))
        let account = app.textFields["requiredAccount"]
        let finish = app.buttons["Import transactions"]
        XCTAssertFalse(finish.isEnabled)
        year.tap()
        app.buttons["2026"].tap()
        account.tap(); account.typeText("Example checking")
        reveal(finish, in: app)
        finish.tap()
        XCTAssertTrue(app.buttons["View and correct transactions"].waitForExistence(timeout: 10))
        app.buttons["View and correct transactions"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Safeway")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("2026-10-02"))
        XCTAssertTrue(row.label.contains("Example checking"))
    }

    @MainActor
    func testConfirmReturnsToListWithAnUnresolvedIssue() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-fixture", "--ui-testing-unresolved-confirmation"]
        app.launch()
        app.buttons["View and correct transactions"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Blue Bottle Oakland")).firstMatch.tap()
        let confirm = app.buttons["Confirm"]
        reveal(confirm, in: app)
        confirm.tap()
        app.buttons["Confirm this transaction only"].tap()
        XCTAssertTrue(app.navigationBars["Transactions"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Review"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Check for a duplicate charge.")).firstMatch.exists)
    }

    @MainActor
    func testManualEntryAndFieldCorrection() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.tabBars.buttons["Import"].tap()
        app.buttons["importInputType"].tap()
        app.buttons["Add transaction manually"].tap()
        let merchant = app.textFields["manualMerchant"]
        XCTAssertTrue(merchant.waitForExistence(timeout: 10))
        merchant.tap(); merchant.typeText("Invented Market")
        let amount = app.textFields["manualAmount"]
        amount.tap(); amount.typeText("12.34")
        app.navigationBars["Add transaction"].buttons["Save"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: merchant)
        waitForExpectations(timeout: 10)
        app.tabBars.buttons["Home"].tap()
        app.buttons["View and correct transactions"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Invented Market")).firstMatch.tap()
        let edited = app.textFields["transactionAmount"]
        XCTAssertTrue(edited.waitForExistence(timeout: 5))
        reveal(edited, in: app)
        edited.tap()
        let clearAmount = app.buttons["clearTransactionAmount"]
        XCTAssertTrue(clearAmount.waitForExistence(timeout: 5))
        clearAmount.tap()
        edited.tap()
        edited.typeText("-20.00")
        reveal(app.buttons["Confirm"], in: app)
        app.buttons["Confirm"].tap()
        let confirmCategory = app.buttons["Confirm this transaction only"]
        XCTAssertTrue(confirmCategory.waitForExistence(timeout: 5))
        confirmCategory.tap()
        XCTAssertTrue(app.navigationBars["Transactions"].waitForExistence(timeout: 5))
        let editedRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Invented Market")).firstMatch
        XCTAssertTrue(editedRow.label.contains("20.00"))
        editedRow.tap()
        app.buttons["transactionDetails"].tap()
        app.buttons["Confidence and evidence"].tap()
        XCTAssertTrue(app.navigationBars["Confidence and evidence"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Evidence"].exists)
    }

    @MainActor
    func testBulkDeletionCanBeCancelledAndConfirmed() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-fixture"]
        app.launch()
        app.buttons["View and correct transactions"].tap()
        app.navigationBars["Transactions"].buttons["Select"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Blue Bottle Oakland")).firstMatch
        reveal(row, in: app)
        XCTAssertTrue(row.exists)
        row.tap()
        let deleteSelected = app.buttons["Delete selected (1)"]
        deleteSelected.tap()
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(row.exists)
        deleteSelected.tap()
        app.alerts.buttons["Delete"].tap()
        XCTAssertFalse(row.exists)
    }

    @MainActor
    func testSourceSwipeOpensEditorAndConfirmsDelete() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-fixture"]
        app.launch()
        app.tabBars.buttons["Sources"].tap()
        let source = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "demo-card-activity.png")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.swipeLeft()
        app.buttons["Edit"].tap()
        let detail = app.navigationBars["demo-card-activity.png"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        detail.buttons.firstMatch.tap()
        source.swipeLeft()
        app.buttons["Delete"].tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(source.exists)
    }

    @MainActor
    func testHomeCategoryFilterOpensMatchingTransactions() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["dashboardMonth"].exists)
        app.buttons["dashboardCategory"].tap()
        app.buttons["Groceries"].tap()
        let matching = app.buttons["View matching transactions"]
        reveal(matching, in: app)
        matching.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Trader Joe")).firstMatch.exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Blue Bottle")).firstMatch.exists)
    }

    @MainActor
    func testMerchantReviewAppliesCategoryAndClearsTheGroup() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-fixture"]
        app.launch()
        app.tabBars.buttons["Review"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Merchant categories")).firstMatch.tap()
        let merchant = app.staticTexts["Blue Bottle Oakland"]
        XCTAssertTrue(merchant.waitForExistence(timeout: 5))
        // Overview row: pick category + Confirm without opening Samples.
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@", "Confirm")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        // Ensure Dining is selected if the menu is available.
        let diningPickers = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Dining"))
        if diningPickers.count == 0 {
            let categoryMenus = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "misc"))
            if categoryMenus.firstMatch.exists {
                categoryMenus.firstMatch.tap()
                app.buttons["Dining"].tap()
            }
        }
        confirm.tap()
        app.buttons["Apply and remember"].tap()
        XCTAssertTrue(app.navigationBars["Merchant categories"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Blue Bottle Oakland"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testReviewImportRepeatAndExport() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-fixture"]
        app.launch()
        app.tabBars.buttons["Review"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Blue Bottle Oakland")).firstMatch.tap()
        let account = app.buttons["transactionAccount"]
        reveal(account, in: app)
        account.tap()
        app.buttons["Checking *9876"].tap()
        XCTAssertTrue(account.label.contains("Checking *9876"))
        let category = app.buttons["transactionCategory"]
        reveal(category, in: app)
        category.tap()
        app.buttons["Dining"].tap()
        reveal(app.buttons["Confirm"], in: app)
        app.buttons["Confirm"].tap()
        app.buttons["Confirm this transaction only"].tap()
        XCTAssertTrue(app.navigationBars["Review"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Blue Bottle Oakland")).firstMatch.exists)
        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.buttons["dashboardMonth"].exists)
        app.tabBars.buttons["Import"].tap()
        app.buttons["importInputType"].tap()
        app.buttons["Paste AI JSON"].tap()
        app.buttons["Import pasted JSON"].tap()
        app.swipeUp()
        let summary = app.staticTexts["importSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        XCTAssertEqual(summary.label, "1 imported · 0 already imported · 0 failed")
        app.swipeDown()
        app.buttons["importInputType"].tap()
        app.buttons["Paste AI JSON"].tap()
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

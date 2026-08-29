import XCTest

final class UltraControllerUITestSmokeTests: XCTestCase {
    func testPlaceholderLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(
            app.descendants(matching: .any)["overview.placeholder"]
                .waitForExistence(timeout: 5)
        )
    }
}

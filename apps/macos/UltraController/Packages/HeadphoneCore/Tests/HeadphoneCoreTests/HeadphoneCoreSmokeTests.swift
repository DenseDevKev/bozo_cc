import XCTest
@testable import HeadphoneCore

final class HeadphoneCoreSmokeTests: XCTestCase {
    func testPackageLoads() {
        XCTAssertEqual(HeadphoneCoreBuild.schemaVersion, 1)
    }
}

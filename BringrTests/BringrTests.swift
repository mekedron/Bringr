import XCTest
@testable import Bringr

final class BringrTests: XCTestCase {
    // Proves the XCTest target builds, links the app via `@testable import`,
    // and runs — the foundation later stories use for fixture-driven tests.
    func testToolingIsWiredUp() {
        XCTAssertTrue(true)
    }
}

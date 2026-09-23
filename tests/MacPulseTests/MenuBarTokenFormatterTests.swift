import XCTest
@testable import MacPulse

final class MenuBarTokenFormatterTests: XCTestCase {
    func testRequestedCompactValues() {
        XCTAssertEqual(MenuBarTokenFormatter.string(217_000_000), "2.17亿")
        XCTAssertEqual(MenuBarTokenFormatter.string(200_000_000), "2亿")
        XCTAssertEqual(MenuBarTokenFormatter.string(1_000_000), "100万")
        XCTAssertEqual(MenuBarTokenFormatter.string(999), "999")
        XCTAssertEqual(MenuBarTokenFormatter.string(1_000), "1千")
    }
    func testRoundingAcrossUnitBoundariesAndInvalidCounts() {
        XCTAssertEqual(MenuBarTokenFormatter.string(999_999), "100万")
        XCTAssertEqual(MenuBarTokenFormatter.string(99_999_999), "1亿")
        XCTAssertEqual(MenuBarTokenFormatter.string(9_999), "1万")
        XCTAssertEqual(MenuBarTokenFormatter.string(21_700_000), "0.217亿")
        XCTAssertEqual(MenuBarTokenFormatter.string(0), "0")
        XCTAssertEqual(MenuBarTokenFormatter.string(-1), "0")
        XCTAssertEqual(MenuBarTokenFormatter.string(Int.max), "922京")
    }
}

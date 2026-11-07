import XCTest
@testable import MacPulse

final class LEDLocalizedReadoutTests: XCTestCase {
    func testArabicDigitsAndDirectionControlsNormalizeWithoutReversingValues() {
        XCTAssertEqual(SevenSegmentText.displayCharacters("\u{2066}USD ١٢٣٫٤٥\u{2069}"), Array("USD 123.45"))
        XCTAssertEqual(SevenSegmentText.displayCharacters("\u{2068}۹۸۷\u{2069}"), Array("987"))
        XCTAssertEqual(SevenSegmentText.displayCharacters("\u{061C}-١٬٢٣٤٫٥"), Array("-1,234.5"))
        XCTAssertEqual(SevenSegmentText.displayCharacters("¥123.45"), Array("¥123.45"))
    }

    func testArabicPhrasesStayJoinedWhileNumericReadoutsRemainSegmented() {
        XCTAssertTrue(SevenSegmentText.requiresJoinedRendering("Codex متاح بنسبة 57%"))
        XCTAssertTrue(SevenSegmentText.requiresJoinedRendering("⁨CNY 123⁩ متاح"))
        XCTAssertFalse(SevenSegmentText.requiresJoinedRendering("USD ١٢٣٫٤٥"))
        XCTAssertFalse(SevenSegmentText.requiresJoinedRendering("¥123.45"))
    }

    func testCountdownUsesElapsedSecondsAtUnitBoundaries() {
        XCTAssertNil(SegTime.from(seconds: 59.999))
        XCTAssertEqual(SegTime.from(seconds: 60)?.digits, "1")
        XCTAssertEqual(SegTime.from(seconds: 3599)?.digits, "59")
        XCTAssertEqual(SegTime.from(seconds: 3600)?.digits, "1:00")
        XCTAssertEqual(SegTime.from(seconds: 3660)?.digits, "1:01")
        XCTAssertEqual(SegTime.from(seconds: 86399)?.digits, "23:59")
        XCTAssertEqual(SegTime.from(seconds: 86400)?.digits, "1:00")
        XCTAssertEqual(SegTime.from(seconds: 93600)?.digits, "1:02")
        XCTAssertNil(SegTime.from(seconds: -.infinity))
        XCTAssertNil(SegTime.from(seconds: .infinity))
        XCTAssertNil(SegTime.from(seconds: .nan))
    }
}

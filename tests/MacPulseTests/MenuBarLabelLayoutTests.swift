import XCTest
import AppKit
@testable import MacPulse

final class MenuBarLabelLayoutTests: XCTestCase {
    func testShortTokenLabelsDoNotReserveLongLabelSpace() {
        let short = MenuBarLabel.renderLabel(fields: [(nil, "1亿", 54)])
        let long = MenuBarLabel.renderLabel(fields: [(nil, "0.217亿", 54)])
        XCTAssertLessThan(short.size.width, long.size.width - 10)
        XCTAssertLessThan(short.size.width, 52)
        XCTAssertEqual(short.size.height, 20)
    }

    func testCompactValuesFitWithoutClipping() {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        for value in ["—", "0", "1亿", "421万", "9999", "0.217亿"] {
            let textWidth = NSAttributedString(string: value, attributes: [.font: font]).size().width
            let image = MenuBarLabel.renderLabel(fields: [(nil, value, 54)])
            XCTAssertGreaterThanOrEqual(image.size.width, 16 + 7 + textWidth, value)
            XCTAssertLessThanOrEqual(image.size.width, 16 + 7 + textWidth + 3, value)
        }
    }
}

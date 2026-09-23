import Foundation

/// Three significant digits, with Chinese units and rollover after rounding.
enum MenuBarTokenFormatter {
    static func string(_ tokens: Int) -> String {
        let value = Double(max(0, tokens))
        guard value >= 1_000 else { return String(max(0, tokens)) }
        let rounded = (value / pow(10, floor(log10(value)) - 2)).rounded()
            * pow(10, floor(log10(value)) - 2)
        let unit: (Double, String)
        if rounded >= 1e16 { unit = (1e16, "京") }
        else if rounded >= 1e12 { unit = (1e12, "万亿") }
        else if rounded >= 1e7 { unit = (1e8, "亿") }
        else if rounded >= 1e4 { unit = (1e4, "万") }
        else { unit = (1e3, "千") }
        let scaled = rounded / unit.0
        let decimals = max(0, 2 - Int(floor(log10(scaled))))
        var number = String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), decimals, scaled)
        if number.contains(".") {
            while number.last == "0" { number.removeLast() }
            if number.last == "." { number.removeLast() }
        }
        return number + unit.1
    }
}

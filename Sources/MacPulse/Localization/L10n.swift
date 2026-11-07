import Foundation

/// Interpolated values are never translation keys; preserve names, paths and numbers verbatim.
struct LocalizedMessage: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    let key: String
    let arguments: [String]
    init(stringLiteral value: String) { key = value; arguments = [] }
    init(stringInterpolation: StringInterpolation) {
        key = stringInterpolation.key
        arguments = stringInterpolation.arguments
    }
    struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []
        init(literalCapacity: Int, interpolationCount: Int) {
            key.reserveCapacity(literalCapacity)
            arguments.reserveCapacity(interpolationCount)
        }
        mutating func appendLiteral(_ literal: String) { key += literal }
        mutating func appendInterpolation<T>(_ value: T) {
            key += "{\(arguments.count)}"
            arguments.append(String(describing: value))
        }
    }
}

enum L10n {
    static let catalog: [String: [String: String]] = {
        #if DEBUG
        let resourceBundle = Bundle.module
        #else
        // SwiftPM's generated accessor embeds an absolute build path. Release bundles
        // load only their packaged resources so no developer home path is shipped.
        let resourceBundle = Bundle.main.url(forResource: "MacPulse_MacPulse", withExtension: "bundle")
            .flatMap(Bundle.init(url:)) ?? Bundle.main
        #endif
        guard let url = resourceBundle.url(forResource: "Translations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { return [:] }
        return entries
    }()

    static func text(_ message: LocalizedMessage) -> String {
        let language = AppLanguage.current
        let template = lookup(message.key, language: language)
        let arguments = language.isRightToLeft
            ? message.arguments.map { "\u{2068}" + $0 + "\u{2069}" } : message.arguments
        return render(template, arguments: arguments)
    }

    static func lookup(_ source: String, language: AppLanguage = .current) -> String {
        guard language != .simplifiedChinese else { return source }
        return catalog[source]?[language.rawValue] ?? catalog[source]?["en"] ?? source
    }

    static func render(_ template: String, arguments: [String]) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\{([0-9]+)\}"#) else { return template }
        let ns = template as NSString
        var result = "", cursor = 0
        for match in regex.matches(in: template, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            if let index = Int(ns.substring(with: match.range(at: 1))), arguments.indices.contains(index) {
                result += arguments[index]
            } else { result += ns.substring(with: match.range) }
            cursor = NSMaxRange(match.range)
        }
        return result + ns.substring(from: cursor)
    }

    static func placeholders(in value: String) -> [String] {
        let pattern = #"\{[0-9]+\}|%(?:[0-9]+\$)?[-+0#]*(?:[0-9]+)?(?:\.[0-9]+)?(?:ll|l|z)?[diuoxXfFeEgGcs@%]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = value as NSString
        return regex.matches(in: value, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range) }.sorted()
    }
}

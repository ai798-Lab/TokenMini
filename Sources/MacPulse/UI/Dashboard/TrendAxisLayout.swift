import Foundation

/// Tick labels are presentation only. The chart keeps every unique bucket key.
struct TrendAxisLayout {
    let points: [TrendPoint]
    let hourly: Bool
    var calendar: Calendar = .current

    func ticks(plotWidth: Double) -> [String] {
        guard !points.isEmpty else { return [] }
        let capacity = max(1, Int(plotWidth / 72))
        let steps = hourly ? [1, 2, 3, 4, 6, 12, 24, 48] : [1, 2, 3, 5, 7, 10, 14, 30, 60]
        for step in steps {
            let indices = points.indices.filter { i in
                hourly ? calendar.component(.hour, from: points[i].date) % step == 0 : i % step == 0
            }
            let gapsFit = zip(indices, indices.dropFirst()).allSatisfy {
                Double($1 - $0) * plotWidth / Double(points.count) >= 72
            }
            if !indices.isEmpty && indices.count <= capacity && gapsFit {
                return indices.map { points[$0].label }
            }
        }
        return [points[0].label]
    }

    func shortLabel(for key: String) -> String {
        guard let point = points.first(where: { $0.label == key }) else { return "" }
        return format(point.date, hourly ? "HH:mm" : "MM/dd")
    }

    struct DateMarker: Identifiable {
        let key: String
        let index: Int
        let text: String
        var id: String { key }
    }

    func dateMarkers(plotWidth: Double) -> [DateMarker] {
        guard hourly, !points.isEmpty else { return [] }
        var indices = points.indices.filter { $0 == 0 || !calendar.isDate(points[$0-1].date, inSameDayAs: points[$0].date) }
        // If midnight is next to the left edge, the interval subtitle already names
        // the previous date. Do not squeeze two date labels into the same space.
        if indices.count > 1 && Double(indices[1]) * plotWidth / Double(points.count) < 64 {
            indices.removeFirst()
        }
        return indices.map { DateMarker(key: points[$0].label, index: $0, text: format(points[$0].date, "MM/dd")) }
    }

    func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

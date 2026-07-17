import Foundation
import IOKit

/// 电池读取器:IOKit AppleSmartBattery 属性字典。台式机无此服务 → present = false。
struct BatteryReader {
    func read() -> BatterySnapshot {
        var snap = BatterySnapshot()
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return snap }            // 台式机
        defer { IOObjectRelease(service) }

        var propsRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = propsRef?.takeRetainedValue() as? [String: Any] else { return snap }

        snap.present = true
        func int(_ k: String) -> Int? { (props[k] as? NSNumber)?.intValue }

        let maxCap = int("MaxCapacity") ?? 100
        let current = int("CurrentCapacity")
        // MaxCapacity==100 时 CurrentCapacity 已是百分比;否则归一化
        if let current {
            let percent = maxCap == 100 ? Double(current)
                : (maxCap > 0 ? Double(current) * 100 / Double(maxCap) : 0)
            snap.currentPercent = Int(min(100, max(0, percent)))
        }

        // 健康度:AppleRawMaxCapacity / DesignCapacity(与系统设置口径一致),封顶 100
        if let raw = int("AppleRawMaxCapacity"), let design = int("DesignCapacity"), design > 0 {
            let percent = Double(raw) * 100 / Double(design)
            snap.healthPercent = Int(min(100, max(0, percent)))
        } else if maxCap <= 100 {
            snap.healthPercent = min(100, max(0, maxCap))
        }

        snap.cycleCount = int("CycleCount").map { max(0, $0) }
        if let t = int("Temperature") {
            let c = Double(t) / 100.0                         // 单位 0.01°C
            if (-20...120).contains(c) { snap.temperatureC = c }
        }
        snap.charging = (props["IsCharging"] as? Bool) ?? false
        snap.externalPower = (props["ExternalConnected"] as? Bool) ?? false
        return snap
    }
}

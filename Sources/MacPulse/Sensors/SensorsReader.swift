import Foundation

/// 温度/风扇采样器,纯 SMC 单路线(M5 上 SMC 温度 key 依然齐全,无需 HID 私有 API)。
/// 只在 SystemMonitor 的 sampleQueue 串行队列上调用,无并发问题。
final class SensorsReader {
    private let smc: SMC?

    /// SMC key 跨芯片代际不稳定(M1 是 Tp09/Tg05,M5 是 Tp00~Tp0y/Tg0U~Tg1g),
    /// 不能硬编码清单——首次 read() 时枚举全部 key 按前缀筛一次并缓存。
    /// 枚举是 3500+ 次 syscall(几十~几百毫秒),必须发生在 sampleQueue 上而不是
    /// init(init 在主线程的 @StateObject 构造链里,会拖慢启动)。
    private var cpuTempKeys: [String] = []
    private var gpuTempKeys: [String] = []
    private var keysLoaded = false

    /// 传感器合理区间,区间外视为垃圾值(个别 key 会返回 0 或负的占位数)
    private static let validRange = 10.0..<130.0

    init() {
        smc = SMC()
    }

    private func loadKeysIfNeeded(smc: SMC) {
        guard !keysLoaded else { return }
        keysLoaded = true
        // 前缀只收 Tp(M5 的 CPU die 全部是 Tp*)和 Te(M4 代际,M5 上匹配 0 个、无害);
        // 不收 Tf——本机实测 TfC* 是异族传感器(疑似闪存/控制器,比 CPU die 低约 5°C),
        // 混入平均会在高负载时把 CPU 温度低报约 10°C。
        let all = smc.getAllKeys()
        cpuTempKeys = all.filter { $0.hasPrefix("Tp") || $0.hasPrefix("Te") }
        gpuTempKeys = all.filter { $0.hasPrefix("Tg") }
    }

    func read() -> SensorSnapshot {
        guard let smc else { return SensorSnapshot() }
        loadKeysIfNeeded(smc: smc)
        var snap = SensorSnapshot()
        snap.cpuTemp = average(of: cpuTempKeys, smc: smc)
        snap.gpuTemp = average(of: gpuTempKeys, smc: smc)
        snap.fans = readFans(smc: smc)
        return snap
    }

    // MARK: - 内部实现

    /// 逐 key 读值,过滤到合理区间后取平均;一个有效值都没有返回 nil
    private func average(of keys: [String], smc: SMC) -> Double? {
        var sum = 0.0
        var count = 0
        for key in keys {
            guard let v = smc.getValue(key), Self.validRange.contains(v) else { continue }
            sum += v
            count += 1
        }
        return count > 0 ? sum / Double(count) : nil
    }

    private func readFans(smc: SMC) -> [FanReading] {
        // FNum 不存在或为 0(无风扇机型)则返回空。
        // 上限钳到 8:FNum >= 10 时 "F\(i)Ac" 变 5 字符,会踩 FourCharCode 的 precondition 崩溃,
        // 真实硬件不超过 4 个风扇,超出的只可能是 SMC 垃圾值。
        guard let num = smc.getValue("FNum"), num > 0 else { return [] }
        var fans: [FanReading] = []
        for i in 0..<min(Int(num), 8) {
            // 当前转速读不到就跳过该风扇;最大转速缺失时填 0,UI 侧自行处理
            guard let current = smc.getValue("F\(i)Ac"), current >= 0, current < 30_000 else { continue }
            let maxValue = smc.getValue("F\(i)Mx") ?? 0
            let maxRPM = (0..<30_000).contains(maxValue) ? maxValue : 0
            fans.append(FanReading(index: i, currentRPM: current, maxRPM: maxRPM))
        }
        return fans
    }
}

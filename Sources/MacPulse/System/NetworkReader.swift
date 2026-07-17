import Foundation
import Darwin

/// 网络吞吐读取器:getifaddrs 按接口做增量再求和,两次采样差值 / 间隔。
/// 状态只在 SystemMonitor 的 sampleQueue 上读写。
struct NetworkReader {
    /// 上次采样的每接口 32 位累计计数(按接口名),回绕差值必须在单接口维度做
    private var prevCounters: [String: (rx: UInt32, tx: UInt32)] = [:]
    private var prevTime: TimeInterval = 0
    private var hasPrev = false

    /// 虚拟/隧道接口前缀:utun(VPN)、ipsec、awdl/llw(AirDrop)、bridge、ap(热点)、
    /// feth/gif/stf(封装)。这些会把同一份流量重复计入(VPN 下约 2 倍虚高),全部排除。
    private static let excludedPrefixes = ["lo", "utun", "ipsec", "awdl", "llw", "bridge", "ap", "feth", "gif", "stf", "anpi"]

    mutating func read() -> NetworkSnapshot {
        let now = Date().timeIntervalSinceReferenceDate
        let counters = Self.readCounters()
        defer {
            prevCounters = counters
            prevTime = now
            hasPrev = true
        }
        guard hasPrev else { return NetworkSnapshot() }
        let elapsed = now - prevTime
        guard elapsed > 0 else { return NetworkSnapshot() }

        // ifi_ibytes/ifi_obytes 是 32 位计数器(100MB/s 时约 43 秒回绕一次),
        // 用 UInt32 &- 做环绕安全差值;新出现的接口本轮丢弃(下轮才有基准)
        var rxDelta: UInt64 = 0
        var txDelta: UInt64 = 0
        for (name, cur) in counters {
            guard let prev = prevCounters[name] else { continue }
            rxDelta &+= UInt64(cur.rx &- prev.rx)
            txDelta &+= UInt64(cur.tx &- prev.tx)
        }
        return NetworkSnapshot(rxPerSec: Double(rxDelta) / elapsed,
                               txPerSec: Double(txDelta) / elapsed)
    }

    private static func readCounters() -> [String: (rx: UInt32, tx: UInt32)] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return [:] }
        defer { freeifaddrs(first) }

        var result: [String: (rx: UInt32, tx: UInt32)] = [:]
        var cursor = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            // 同名接口有 AF_INET/AF_INET6/AF_LINK 多条,只有 AF_LINK 的 ifa_data 才是 if_data,
            // 判断错会把别的结构当统计读到垃圾内存
            guard let addr = entry.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let flags = Int32(bitPattern: entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            guard !excludedPrefixes.contains(where: { name.hasPrefix($0) }) else { continue }
            guard let raw = entry.pointee.ifa_data else { continue }
            let data = raw.assumingMemoryBound(to: if_data.self).pointee
            // 同一接口理论上只有一条 AF_LINK;若重复出现保留最后一条
            result[name] = (data.ifi_ibytes, data.ifi_obytes)
        }
        return result
    }
}

import Foundation
import Combine

/// 各 Reader 的容器:全部状态只在 sampleQueue 串行队列上读写。
/// 契约:各 Reader 由独立文件实现 ——
///   CPUReader:     `mutating func read() -> CPUSnapshot`(内部保存上次 tick 计数)
///   MemoryReader:  `func read() -> MemorySnapshot`
///   NetworkReader: `mutating func read() -> NetworkSnapshot`(内部保存上次计数与时间)
///   DiskReader:    `mutating func read() -> DiskSnapshot`(内部保存上次计数与时间)
///   ProcessReader: `static func topProcesses(limit: Int) -> [TopProcess]`
///   SensorsReader: `final class`,`func read() -> SensorSnapshot`
private final class Samplers: @unchecked Sendable {
    var cpu = CPUReader()
    let mem = MemoryReader()
    var net = NetworkReader()
    var disk = DiskReader()
    let sensors = SensorsReader()
    let battery = BatteryReader()
    let diskSpace = DiskSpaceReader()
}

/// 系统监控调度中心:定时采样,发布快照与历史序列供 UI 订阅。
@MainActor
final class SystemMonitor: ObservableObject {
    @Published var cpu = CPUSnapshot()
    @Published var memory = MemorySnapshot()
    @Published var network = NetworkSnapshot()
    @Published var disk = DiskSnapshot()
    @Published var sensors = SensorSnapshot()
    @Published var topProcesses: [TopProcess] = []       // 按 CPU 排序
    @Published var topProcessesByMemory: [TopProcess] = []
    @Published var battery = BatterySnapshot()
    @Published var diskSpace = DiskSpaceSnapshot()

    /// 最近 N 个采样点(0~1),驱动折线图
    @Published var cpuHistory: [Double] = []
    @Published var memHistory: [Double] = []

    static let historyLength = 60
    static let fastInterval: TimeInterval = 2    // CPU/内存/网络/磁盘
    static let slowInterval: TimeInterval = 6    // 传感器 + 进程列表

    private let samplers = Samplers()
    private let sampleQueue = DispatchQueue(label: "macpulse.sampling", qos: .utility)
    private var fastTimer: Timer?
    private var slowTimer: Timer?
    // 在途保护:采样耗时超过间隔时(高负载下 ps 可能秒级)跳过本轮,
    // 避免工作项在串行队列上无界积压、恢复后连发过期快照
    private var fastInFlight = false
    private var slowInFlight = false

    func start() {
        guard fastTimer == nil else { return }
        fastTick()
        slowTick()
        // 必须挂 .common 模式:scheduledTimer 默认挂 default 模式,
        // 用户在弹窗里拖动/滚动进入 event-tracking 模式时刷新会整体冻结
        let fast = Timer(timeInterval: Self.fastInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.fastTick() }
        }
        let slow = Timer(timeInterval: Self.slowInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.slowTick() }
        }
        fast.tolerance = 0.5
        slow.tolerance = 1.0
        RunLoop.main.add(fast, forMode: .common)
        RunLoop.main.add(slow, forMode: .common)
        fastTimer = fast
        slowTimer = slow
    }

    func refresh() {
        fastTick()
        slowTick()
    }

    func stop() {
        fastTimer?.invalidate(); fastTimer = nil
        slowTimer?.invalidate(); slowTimer = nil
    }

    private func fastTick() {
        guard !fastInFlight else { return }
        fastInFlight = true
        let samplers = self.samplers
        sampleQueue.async { [weak self] in
            let cpu = samplers.cpu.read()
            let mem = samplers.mem.read()
            let net = samplers.net.read()
            let dsk = samplers.disk.read()
            Task { @MainActor in
                guard let self else { return }
                self.fastInFlight = false
                self.cpu = cpu
                self.memory = mem
                self.network = net
                self.disk = dsk
                self.pushHistory(cpu: cpu.totalUsage, mem: mem.usageRatio)
            }
        }
    }

    private func slowTick() {
        guard !slowInFlight else { return }
        slowInFlight = true
        let samplers = self.samplers
        sampleQueue.async { [weak self] in
            let sensors = samplers.sensors.read()
            let procs = ProcessReader.topProcesses(limit: 6, sortBy: .cpu)
            let procsByMem = ProcessReader.topProcesses(limit: 6, sortBy: .memory)
            let battery = samplers.battery.read()
            let diskSpace = samplers.diskSpace.read()
            Task { @MainActor in
                guard let self else { return }
                self.slowInFlight = false
                self.sensors = sensors
                self.topProcesses = procs
                self.topProcessesByMemory = procsByMem
                self.battery = battery
                self.diskSpace = diskSpace
            }
        }
    }

    private func pushHistory(cpu: Double, mem: Double) {
        cpuHistory.append(cpu)
        memHistory.append(mem)
        if cpuHistory.count > Self.historyLength { cpuHistory.removeFirst(cpuHistory.count - Self.historyLength) }
        if memHistory.count > Self.historyLength { memHistory.removeFirst(memHistory.count - Self.historyLength) }
    }
}

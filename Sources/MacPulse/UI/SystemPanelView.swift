import SwiftUI
import Charts

/// 系统页签:监控(CPU/内存/网络/磁盘/传感器/电池/进程)+ 清理优化(内存回收/进程结束/垃圾清理)。
/// 清理是系统管理的一部分,收在本页而非独立 tab。HUD 模块化面板布局。
struct HUDSystemPanelView: View {
    @EnvironmentObject var system: SystemMonitor
    @EnvironmentObject var cleanup: CleanupStore
    @State private var procToKill: TopProcess?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            cpuSection
            memorySection
            ratesAndDiskSection
            batterySection
            processSection
            junkSection
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .onAppear {
            if !cleanup.hasScanned && !cleanup.scanning { cleanup.scan() }
        }
        .alert("结束进程", isPresented: Binding(
            get: { procToKill != nil },
            set: { if !$0 { procToKill = nil } })
        ) {
            Button("取消", role: .cancel) { procToKill = nil }
            Button("结束", role: .destructive) {
                if let p = procToKill { ProcessKiller.terminate(pid: p.pid, expectedName: p.name) }
                procToKill = nil
            }
        } message: {
            if let p = procToKill {
                Text("将向「\(p.name)」发送退出信号(等同 Cmd-Q,应用会先保存)。确定结束吗?")
            }
        }
    }

    // MARK: CPU

    private var cpuSection: some View {
        HUDPanel(padding: 9, accent: HUD.load(system.cpu.totalUsage)) {
            VStack(alignment: .leading, spacing: 5) {
                HUDSectionHeader(cn: "CPU", code: "SYS.CPU // LOAD",
                                 accent: HUD.load(system.cpu.totalUsage),
                                 trailing: AnyView(cpuReadout))
                Sparkline(values: system.cpuHistory, color: HUD.cyan)
                    .frame(height: 36)
                HStack(spacing: 12) {
                    legend("系统", String(format: "%.1f%%", system.cpu.systemUsage * 100), HUD.pink)
                    legend("用户", String(format: "%.1f%%", system.cpu.userUsage * 100), HUD.cyan)
                    Spacer()
                }
            }
        }
    }

    private var cpuReadout: some View {
        HStack(spacing: 8) {
            if let t = system.sensors.cpuTemp {
                Text(String(format: "%.0f°C", t))
                    .font(HUD.mono(9, .medium))
                    .foregroundStyle(t > 85 ? HUD.red : HUD.dim)
            }
            Text(String(format: "%.1f%%", system.cpu.totalUsage * 100))
                .font(HUD.mono(13, .bold))
                .foregroundStyle(HUD.load(system.cpu.totalUsage))
        }
    }

    // MARK: 内存(含一键回收)

    private var memorySection: some View {
        HUDPanel(padding: 9, accent: memColor) {
            VStack(alignment: .leading, spacing: 5) {
                HUDSectionHeader(cn: "内存", code: "SYS.MEM", accent: memColor,
                                 trailing: AnyView(
                                    Text("\(ByteFormat.memory(system.memory.used)) / \(ByteFormat.memory(system.memory.total))")
                                        .font(HUD.mono(10, .bold))
                                        .foregroundStyle(HUD.text)))
                HUDGauge(ratio: system.memory.usageRatio, color: memColor)
                HStack(spacing: 12) {
                    legend("联动", ByteFormat.memory(system.memory.wired), HUD.amber)
                    legend("已压缩", ByteFormat.memory(system.memory.compressed), HUD.violet)
                    Spacer()
                    if let freed = cleanup.lastFreedMemory {
                        Text(freed > 0 ? "已回收 \(ByteFormat.memory(UInt64(freed)))" : "已最优")
                            .font(HUD.mono(8))
                            .foregroundStyle(freed > 0 ? HUD.green : HUD.dim)
                    }
                    Button {
                        cleanup.releaseMemory()
                    } label: {
                        HStack(spacing: 3) {
                            if cleanup.releasingMemory { ProgressView().controlSize(.mini) }
                            Text(cleanup.releasingMemory ? "回收中" : "回收内存")
                        }
                    }
                    .buttonStyle(HUDButtonStyle(size: 9))
                    .disabled(cleanup.releasingMemory)
                }
            }
        }
    }

    private var memColor: Color {
        let r = system.memory.usageRatio
        return r > 0.9 ? HUD.red : (r > 0.75 ? HUD.amber : HUD.green)
    }

    // MARK: 网络 + 磁盘速率 + 磁盘容量(合并一个面板)

    private var ratesAndDiskSection: some View {
        HUDPanel(padding: 9) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 0) {
                    rateCell(icon: "network", title: "NET",
                             l1: "↓ \(ByteFormat.string(system.network.rxPerSec))/s",
                             l2: "↑ \(ByteFormat.string(system.network.txPerSec))/s")
                    Rectangle().fill(HUD.gridline).frame(width: 1, height: 26)
                    rateCell(icon: "internaldrive", title: "I/O",
                             l1: "读 \(ByteFormat.string(system.disk.readPerSec))/s",
                             l2: "写 \(ByteFormat.string(system.disk.writePerSec))/s")
                }
                HUDSectionHeader(cn: "磁盘空间", code: "SYS.DISK",
                                 accent: system.diskSpace.usedRatio > 0.9 ? HUD.red : HUD.cyan,
                                 trailing: AnyView(
                                    Text("可用 \(ByteFormat.memory(system.diskSpace.free)) / \(ByteFormat.memory(system.diskSpace.total))")
                                        .font(HUD.mono(8))
                                        .foregroundStyle(HUD.dim)))
                HUDGauge(ratio: system.diskSpace.usedRatio,
                         color: system.diskSpace.usedRatio > 0.9 ? HUD.red : HUD.cyan,
                         height: 5)
                sensorRow
            }
        }
    }

    private func rateCell(icon: String, title: String, l1: String, l2: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(HUD.dim).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(title).font(HUD.mono(7, .medium)).kerning(0.8).foregroundStyle(HUD.faint)
                }
                Text(l1).font(HUD.mono(9)).foregroundStyle(HUD.text)
                Text(l2).font(HUD.mono(9)).foregroundStyle(HUD.dim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    // MARK: 传感器(并入磁盘面板尾行)

    @ViewBuilder
    private var sensorRow: some View {
        if system.sensors.gpuTemp != nil || !system.sensors.fans.isEmpty {
            HStack(spacing: 12) {
                if let g = system.sensors.gpuTemp {
                    legend("GPU", String(format: "%.0f°C", g), HUD.mint)
                }
                ForEach(system.sensors.fans) { fan in
                    legend("风扇\(fan.index + 1)", String(format: "%.0f rpm", fan.currentRPM), HUD.ice)
                }
                Spacer()
            }
        }
    }

    // MARK: 电池

    @ViewBuilder
    private var batterySection: some View {
        if system.battery.present {
            HUDPanel(padding: 9, accent: HUD.green) {
                HStack(spacing: 12) {
                    HUDSectionHeader(cn: "电池", code: "SYS.PWR", accent: HUD.green,
                                     trailing: AnyView(batteryReadout))
                }
            }
        }
    }

    private var batteryReadout: some View {
        HStack(spacing: 10) {
            Image(systemName: batteryIcon).font(.system(size: 9)).foregroundStyle(HUD.dim)
            if let p = system.battery.currentPercent {
                Text("\(p)%").font(HUD.mono(10, .bold)).foregroundStyle(HUD.text)
            }
            if let h = system.battery.healthPercent {
                legend("健康", "\(h)%", h >= 80 ? HUD.green : HUD.amber)
            }
            if let c = system.battery.cycleCount {
                legend("循环", "\(c)", HUD.dim)
            }
            if let t = system.battery.temperatureC {
                legend("温度", String(format: "%.0f°C", t), HUD.dim)
            }
        }
    }

    private var batteryIcon: String {
        if system.battery.charging { return "battery.100.bolt" }
        return system.battery.externalPower ? "powerplug" : "battery.100"
    }

    // MARK: 进程(含结束)

    private var processSection: some View {
        HUDPanel(padding: 9, accent: HUD.violet) {
            VStack(alignment: .leading, spacing: 4) {
                HUDSectionHeader(cn: "占用最高", code: "PROC.TOP", accent: HUD.violet)
                ForEach(Array(system.topProcesses.enumerated()), id: \.element.id) { i, p in
                    HStack(spacing: 6) {
                        Text(String(format: "%02d", i + 1))
                            .font(HUD.mono(8, .medium)).foregroundStyle(HUD.faint)
                        Text(p.name).font(.system(size: 10)).foregroundStyle(HUD.text).lineLimit(1)
                        Spacer()
                        Text(ByteFormat.memory(p.memoryBytes))
                            .font(HUD.mono(8))
                            .foregroundStyle(HUD.faint)
                            .frame(width: 62, alignment: .trailing)
                        Text(String(format: "%.1f%%", p.cpuPercent))
                            .font(HUD.mono(9, .medium))
                            .foregroundStyle(p.cpuPercent > 80 ? HUD.amber : HUD.dim)
                            .frame(width: 48, alignment: .trailing)
                        Button {
                            procToKill = p
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
                                .foregroundStyle(HUD.faint)
                                .frame(width: 12, height: 12)
                                .background(CutCorner(cut: 3).fill(Color.white.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                        .help("结束该进程")
                    }
                    .padding(.vertical, 1)
                    .hudRowHover()
                }
            }
        }
    }

    // MARK: 垃圾清理

    private var junkSection: some View {
        HUDPanel(padding: 9, accent: HUD.amber) {
            VStack(alignment: .leading, spacing: 6) {
                HUDSectionHeader(cn: "垃圾清理", code: "SYS.JUNK", accent: HUD.amber,
                                 trailing: AnyView(junkHeaderTrailing))

                ForEach(cleanup.results) { result in
                    Button {
                        cleanup.toggle(result.category)
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            let on = cleanup.selected.contains(result.category)
                            Image(systemName: on ? "checkmark.square.fill" : "square")
                                .font(.system(size: 11))
                                .foregroundStyle(on ? HUD.cyan : HUD.faint)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack {
                                    Text(result.category.title)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(HUD.text)
                                    Spacer()
                                    Text(ByteFormat.memory(UInt64(max(0, result.totalBytes))))
                                        .font(HUD.mono(9))
                                        .foregroundStyle(HUD.dim)
                                }
                                Text(result.category.subtitle)
                                    .font(.system(size: 8.5)).foregroundStyle(HUD.faint)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hudRowHover()
                }

                HStack {
                    if let r = cleanup.lastReport {
                        Text("已清理 \(ByteFormat.memory(UInt64(max(0, r.freedBytes))))" +
                             (r.failedCount > 0 ? " · \(r.failedCount) 项占用中跳过" : ""))
                            .font(HUD.mono(8)).foregroundStyle(HUD.green)
                    } else {
                        Text("已选 \(ByteFormat.memory(UInt64(max(0, cleanup.selectedBytes))))")
                            .font(HUD.mono(8)).foregroundStyle(HUD.dim)
                    }
                    Spacer()
                    Button {
                        cleanup.clean()
                    } label: {
                        HStack(spacing: 4) {
                            if cleanup.cleaning { ProgressView().controlSize(.mini) }
                            Text(cleanup.cleaning ? "清理中…" : "清理选中")
                        }
                    }
                    .buttonStyle(HUDButtonStyle(accent: HUD.amber, filled: true, size: 10))
                    .disabled(cleanup.cleaning || cleanup.scanning || cleanup.selected.isEmpty || cleanup.selectedBytes == 0)
                }
            }
        }
    }

    @ViewBuilder
    private var junkHeaderTrailing: some View {
        if cleanup.scanning {
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("扫描中…").font(HUD.mono(8)).foregroundStyle(HUD.dim)
            }
        } else {
            Button("重新扫描") { cleanup.scan() }
                .buttonStyle(HUDButtonStyle(accent: HUD.amber, size: 8))
                .disabled(cleanup.cleaning)
        }
    }

    // MARK: 小组件

    private func legend(_ name: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Rectangle().fill(color).frame(width: 6, height: 6)
            Text(name).font(.system(size: 9)).foregroundStyle(HUD.dim)
            Text(value).font(HUD.mono(9)).foregroundStyle(HUD.text.opacity(0.85))
        }
    }
}

/// 迷你折线图(帧内填充渐变)
struct Sparkline: View {
    let values: [Double]           // 0~1
    let color: Color

    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { i, v in
            AreaMark(x: .value("t", i), y: .value("v", v))
                .foregroundStyle(.linearGradient(
                    colors: [color.opacity(0.35), color.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("t", i), y: .value("v", v))
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...1)
        .chartXScale(domain: 0...max(SystemMonitor.historyLength - 1, 1))
    }
}

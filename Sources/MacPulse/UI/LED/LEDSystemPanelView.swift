import SwiftUI

/// LED 主题·系统页签:监控(CPU/内存/网络/磁盘/传感器/电池/进程)+ 清理优化。
/// 视觉映射:一个分区一块 LED 显示屏,屏色按功能类别取(负载类交给 LED.level 自动变色);
/// 只有真正的主角数值(CPU 百分比 / 已用内存)才配七段数码管,其余走 LED.mono。
/// (Sparkline 与 HUD/经典主题共享,定义在 SystemPanelView.swift)
struct LEDSystemPanelView: View {
    @EnvironmentObject var system: SystemMonitor
    @EnvironmentObject var cleanup: CleanupStore
    @State private var procToKill: TopProcess?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            cpuSection
            memorySection
            ratesSection
            diskSpaceSection
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

    /// 负载越高整块屏越红——LED.level 统一取色,不在各处手写阈值三元
    private var cpuColor: Color { LED.level(system.cpu.totalUsage) }

    private var cpuSection: some View {
        LEDPanel(tint: cpuColor, padding: 11) {
            VStack(alignment: .leading, spacing: 7) {
                sectionHeader("CPU LOAD", cn: "CPU", tint: cpuColor) {
                    if let t = system.sensors.cpuTemp {
                        Text(String(format: "%.0f°C", t))
                            .font(LED.mono(9, .medium))
                            .foregroundStyle(t > 85 ? LED.red : LED.dim)
                    }
                }
                HStack(alignment: .bottom, spacing: 8) {
                    SevenSegmentText(text: String(format: "%.1f", system.cpu.totalUsage * 100),
                                     height: 26, color: cpuColor)
                    LEDCaption(text: "PERCENT", tint: cpuColor, size: 8)
                        .padding(.bottom, 3)
                    Spacer()
                    LEDChevrons(pointingRight: true, count: 4, tint: cpuColor, size: 7)
                        .padding(.bottom, 4)
                }
                // 折线跟着负载色走,否则低负载时绿屏上一条红线,视觉打架
                Sparkline(values: system.cpuHistory, color: cpuColor)
                    .frame(height: 32)
                HStack(spacing: 12) {
                    legend("系统", String(format: "%.1f%%", system.cpu.systemUsage * 100), LED.red)
                    legend("用户", String(format: "%.1f%%", system.cpu.userUsage * 100), LED.amber)
                    Spacer()
                }
            }
        }
    }

    // MARK: 内存(含一键回收)

    private var memColor: Color { LED.level(system.memory.usageRatio, warn: 0.75, bad: 0.9) }

    /// 数码管要的是裸数字,ByteFormat.memory 带单位串,故按 1024 进制单独换算(与它口径一致)
    private var memUsedGB: String {
        String(format: "%.1f", Double(system.memory.used) / 1_073_741_824)
    }

    private var memorySection: some View {
        LEDPanel(tint: memColor, padding: 11) {
            VStack(alignment: .leading, spacing: 7) {
                sectionHeader("MEMORY", cn: "内存", tint: memColor) { EmptyView() }
                HStack(alignment: .bottom, spacing: 7) {
                    SevenSegmentText(text: memUsedGB, height: 20, color: memColor)
                    Text("GB / \(ByteFormat.memory(system.memory.total))")
                        .font(LED.mono(9, .bold))
                        .foregroundStyle(LED.text.opacity(0.85))
                        .padding(.bottom, 2)
                    Spacer()
                }
                LEDGauge(ratio: system.memory.usageRatio, color: memColor)
                HStack(spacing: 12) {
                    legend("联动", ByteFormat.memory(system.memory.wired), LED.amber)
                    legend("已压缩", ByteFormat.memory(system.memory.compressed), LED.green)
                    Spacer()
                    if let freed = cleanup.lastFreedMemory {
                        Text(freed > 0 ? "已回收 \(ByteFormat.memory(UInt64(freed)))" : "已最优")
                            .font(LED.mono(8))
                            .foregroundStyle(freed > 0 ? LED.green : LED.dim)
                    }
                    Button {
                        cleanup.releaseMemory()
                    } label: {
                        HStack(spacing: 3) {
                            if cleanup.releasingMemory { ProgressView().controlSize(.mini) }
                            Text(cleanup.releasingMemory ? "回收中" : "回收内存")
                        }
                    }
                    .buttonStyle(LEDGhostButtonStyle(size: 9))
                    .disabled(cleanup.releasingMemory)
                }
            }
        }
    }

    // MARK: 网络 + 磁盘速率

    private var ratesSection: some View {
        LEDPanel(tint: LED.green, padding: 11) {
            HStack(spacing: 0) {
                rateCell(code: "NETWORK", cn: "网络", icon: "network",
                         l1: "↓ \(ByteFormat.string(system.network.rxPerSec))/s",
                         l2: "↑ \(ByteFormat.string(system.network.txPerSec))/s")
                Capsule().fill(LED.green.opacity(0.22)).frame(width: 1, height: 30)
                rateCell(code: "DISK I/O", cn: "磁盘", icon: "internaldrive",
                         l1: "读 \(ByteFormat.string(system.disk.readPerSec))/s",
                         l2: "写 \(ByteFormat.string(system.disk.writePerSec))/s")
            }
        }
    }

    private func rateCell(code: String, cn: String, icon: String, l1: String, l2: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(LED.green.opacity(0.85))
                .shadow(color: LED.green.opacity(0.5), radius: 3)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    LEDCaption(text: code, tint: LED.green, size: 7)
                    Text(cn).font(LED.display(9, .semibold)).foregroundStyle(LED.dim)
                }
                Text(l1).font(LED.mono(9)).foregroundStyle(LED.text)
                Text(l2).font(LED.mono(9)).foregroundStyle(LED.dim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    // MARK: 磁盘空间(传感器并入尾行,与 HUD 版分组一致)

    private var diskColor: Color { LED.level(system.diskSpace.usedRatio) }

    private var diskSpaceSection: some View {
        LEDPanel(tint: diskColor, padding: 11) {
            VStack(alignment: .leading, spacing: 7) {
                sectionHeader("DISK SPACE", cn: "磁盘空间", tint: diskColor) {
                    Text("可用 \(ByteFormat.memory(system.diskSpace.free)) / \(ByteFormat.memory(system.diskSpace.total))")
                        .font(LED.mono(8))
                        .foregroundStyle(LED.dim)
                }
                LEDGauge(ratio: system.diskSpace.usedRatio, color: diskColor, height: 6)
                sensorRow
            }
        }
    }

    // MARK: 传感器

    @ViewBuilder
    private var sensorRow: some View {
        if system.sensors.gpuTemp != nil || !system.sensors.fans.isEmpty {
            HStack(spacing: 12) {
                if let g = system.sensors.gpuTemp {
                    legend("GPU", String(format: "%.0f°C", g), LED.red)
                }
                ForEach(system.sensors.fans) { fan in
                    legend("风扇\(fan.index + 1)", String(format: "%.0f rpm", fan.currentRPM), LED.green)
                }
                Spacer()
            }
        }
    }

    // MARK: 电池

    @ViewBuilder
    private var batterySection: some View {
        if system.battery.present {
            LEDPanel(tint: LED.green, padding: 11) {
                // 电量 + 三项指标塞不进标头右侧(340pt 弹窗会把中文标签挤到换行),拆两行
                VStack(alignment: .leading, spacing: 6) {
                    sectionHeader("BATTERY", cn: "电池", tint: LED.green) {
                        HStack(spacing: 6) {
                            Image(systemName: batteryIcon).font(.system(size: 9)).foregroundStyle(LED.dim)
                            if let p = system.battery.currentPercent {
                                Text("\(p)%").font(LED.mono(10, .bold)).foregroundStyle(LED.text)
                            }
                        }
                    }
                    batteryReadout
                }
            }
        }
    }

    private var batteryReadout: some View {
        HStack(spacing: 12) {
            if let h = system.battery.healthPercent {
                legend("健康", "\(h)%", h >= 80 ? LED.green : LED.amber)
            }
            if let c = system.battery.cycleCount {
                legend("循环", "\(c)", LED.faint)
            }
            if let t = system.battery.temperatureC {
                legend("温度", String(format: "%.0f°C", t), LED.faint)
            }
            Spacer()
        }
    }

    private var batteryIcon: String {
        if system.battery.charging { return "battery.100.bolt" }
        return system.battery.externalPower ? "powerplug" : "battery.100"
    }

    // MARK: 进程(含结束)

    private var processSection: some View {
        LEDPanel(tint: LED.red, padding: 11) {
            VStack(alignment: .leading, spacing: 4) {
                sectionHeader("TOP PROCESSES", cn: "占用最高", tint: LED.red) { EmptyView() }
                ForEach(Array(system.topProcesses.enumerated()), id: \.element.id) { i, p in
                    HStack(spacing: 6) {
                        Text(String(format: "%02d", i + 1))
                            .font(LED.mono(8, .medium)).foregroundStyle(LED.faint)
                        Text(p.name).font(.system(size: 10)).foregroundStyle(LED.text).lineLimit(1)
                        Spacer()
                        Text(ByteFormat.memory(p.memoryBytes))
                            .font(LED.mono(8))
                            .foregroundStyle(LED.faint)
                            .frame(width: 62, alignment: .trailing)
                        Text(String(format: "%.1f%%", p.cpuPercent))
                            .font(LED.mono(9, .medium))
                            .foregroundStyle(LED.level(p.cpuPercent / 100))
                            .frame(width: 48, alignment: .trailing)
                        Button {
                            procToKill = p
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
                                .foregroundStyle(LED.faint)
                                .frame(width: 14, height: 14)
                                .background(Circle().fill(Color.white.opacity(0.07)))
                        }
                        .buttonStyle(.plain)
                        .help("结束该进程")
                    }
                    .padding(.vertical, 1)
                    .ledRowHover()
                }
            }
        }
    }

    // MARK: 垃圾清理

    private var junkSection: some View {
        LEDPanel(tint: LED.amber, padding: 11) {
            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("JUNK CLEANUP", cn: "垃圾清理", tint: LED.amber) { junkHeaderTrailing }

                ForEach(cleanup.results) { result in
                    Button {
                        cleanup.toggle(result.category)
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            let on = cleanup.selected.contains(result.category)
                            Image(systemName: on ? "checkmark.square.fill" : "square")
                                .font(.system(size: 11))
                                .foregroundStyle(on ? LED.amber : LED.faint)
                                .shadow(color: LED.amber.opacity(on ? 0.6 : 0), radius: 3)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack {
                                    Text(result.category.title)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(LED.text)
                                    Spacer()
                                    Text(ByteFormat.memory(UInt64(max(0, result.totalBytes))))
                                        .font(LED.mono(9))
                                        .foregroundStyle(LED.dim)
                                }
                                Text(result.category.subtitle)
                                    .font(.system(size: 8.5)).foregroundStyle(LED.faint)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .ledRowHover()
                }

                HStack {
                    if let r = cleanup.lastReport {
                        Text("已清理 \(ByteFormat.memory(UInt64(max(0, r.freedBytes))))" +
                             (r.failedCount > 0 ? " · \(r.failedCount) 项占用中跳过" : ""))
                            .font(LED.mono(8)).foregroundStyle(LED.green)
                    } else {
                        Text("已选 \(ByteFormat.memory(UInt64(max(0, cleanup.selectedBytes))))")
                            .font(LED.mono(8)).foregroundStyle(LED.dim)
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
                    .buttonStyle(LEDGhostButtonStyle(size: 10, prominent: true))
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
                Text("扫描中…").font(LED.mono(8)).foregroundStyle(LED.dim)
            }
        } else {
            Button("重新扫描") { cleanup.scan() }
                .buttonStyle(LEDGhostButtonStyle(size: 9))
                .disabled(cleanup.cleaning)
        }
    }

    // MARK: 小组件

    /// 分区标头:英文代号(LED 小标注)+ 中文名,右侧挂读数
    private func sectionHeader<T: View>(_ code: String, cn: String, tint: Color,
                                        @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: 7) {
            LEDCaption(text: code, tint: tint)
            Text(cn).font(LED.display(11)).foregroundStyle(LED.text.opacity(0.9))
            Spacer()
            trailing()
        }
    }

    /// 图例小项:发光圆点(方块是 HUD 的语言,LED 一律圆)
    private func legend(_ name: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
                .shadow(color: color.opacity(0.8), radius: 2.5)
            Text(name).font(.system(size: 9)).foregroundStyle(LED.dim)
            Text(value).font(LED.mono(9)).foregroundStyle(LED.text.opacity(0.85))
        }
    }
}

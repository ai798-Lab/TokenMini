import SwiftUI
import Charts

/// 经典主题·系统页签:监控(CPU/内存/网络/磁盘/传感器/电池/进程)+ 清理优化。
/// (Sparkline 与 HUD 主题共享,定义在 SystemPanelView.swift)
struct ClassicSystemPanelView: View {
    @EnvironmentObject var system: SystemMonitor
    @EnvironmentObject var cleanup: CleanupStore
    @State private var procToKill: TopProcess?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            cpuSection
            memorySection
            ratesSection
            diskSpaceSection
            sensorSection
            batterySection
            processSection

            Divider().padding(.vertical, 2)
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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                sectionTitle("CPU", icon: "cpu")
                Spacer()
                if let t = system.sensors.cpuTemp {
                    Text(String(format: "%.0f°C", t))
                        .font(.caption)
                        .foregroundStyle(t > 85 ? .red : .secondary)
                }
                Text(String(format: "%.1f%%", system.cpu.totalUsage * 100))
                    .font(.system(.body, design: .monospaced).weight(.semibold))
            }
            Sparkline(values: system.cpuHistory, color: .blue)
                .frame(height: 36)
            HStack(spacing: 12) {
                legend("系统", String(format: "%.1f%%", system.cpu.systemUsage * 100), .red)
                legend("用户", String(format: "%.1f%%", system.cpu.userUsage * 100), .blue)
                Spacer()
            }
        }
    }

    // MARK: 内存(含一键回收)

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                sectionTitle("内存", icon: "memorychip")
                Spacer()
                Text("\(ByteFormat.memory(system.memory.used)) / \(ByteFormat.memory(system.memory.total))")
                    .font(.system(.body, design: .monospaced).weight(.semibold))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(.quaternary)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(memColor)
                        .frame(width: max(4, geo.size.width * system.memory.usageRatio))
                }
            }
            .frame(height: 6)
            HStack(spacing: 12) {
                legend("联动", ByteFormat.memory(system.memory.wired), .orange)
                legend("已压缩", ByteFormat.memory(system.memory.compressed), .purple)
                Spacer()
                if let freed = cleanup.lastFreedMemory {
                    Text(freed > 0 ? "已回收 \(ByteFormat.memory(UInt64(freed)))" : "已最优")
                        .font(.caption2)
                        .foregroundStyle(freed > 0 ? .green : .secondary)
                }
                Button {
                    cleanup.releaseMemory()
                } label: {
                    HStack(spacing: 3) {
                        if cleanup.releasingMemory { ProgressView().controlSize(.mini) }
                        Text(cleanup.releasingMemory ? "回收中" : "回收内存")
                    }
                }
                .controlSize(.mini)
                .disabled(cleanup.releasingMemory)
            }
        }
    }

    private var memColor: Color {
        let r = system.memory.usageRatio
        return r > 0.9 ? .red : (r > 0.75 ? .orange : .green)
    }

    // MARK: 网络 + 磁盘速率

    private var ratesSection: some View {
        HStack(spacing: 0) {
            rateCell(icon: "network", title: "网络",
                     l1: "↓ \(ByteFormat.string(system.network.rxPerSec))/s",
                     l2: "↑ \(ByteFormat.string(system.network.txPerSec))/s")
            Divider().frame(height: 28)
            rateCell(icon: "internaldrive", title: "磁盘",
                     l1: "读 \(ByteFormat.string(system.disk.readPerSec))/s",
                     l2: "写 \(ByteFormat.string(system.disk.writePerSec))/s")
        }
    }

    private func rateCell(icon: String, title: String, l1: String, l2: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(l1).font(.system(.caption, design: .monospaced))
                Text(l2).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    // MARK: 磁盘容量

    private var diskSpaceSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                sectionTitle("磁盘空间", icon: "externaldrive")
                Spacer()
                Text("可用 \(ByteFormat.memory(system.diskSpace.free)) / \(ByteFormat.memory(system.diskSpace.total))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(.quaternary)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(system.diskSpace.usedRatio > 0.9 ? Color.red : .accentColor)
                        .frame(width: max(4, geo.size.width * system.diskSpace.usedRatio))
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: 传感器

    @ViewBuilder
    private var sensorSection: some View {
        if system.sensors.gpuTemp != nil || !system.sensors.fans.isEmpty {
            HStack(spacing: 12) {
                if let g = system.sensors.gpuTemp {
                    legend("GPU", String(format: "%.0f°C", g), .teal)
                }
                ForEach(system.sensors.fans) { fan in
                    legend("风扇\(fan.index + 1)", String(format: "%.0f rpm", fan.currentRPM), .gray)
                }
                Spacer()
            }
        }
    }

    // MARK: 电池

    @ViewBuilder
    private var batterySection: some View {
        if system.battery.present {
            HStack(spacing: 12) {
                sectionTitle("电池", icon: batteryIcon)
                if let p = system.battery.currentPercent {
                    Text("\(p)%").font(.system(.caption, design: .monospaced).weight(.semibold))
                }
                if let h = system.battery.healthPercent {
                    legend("健康", "\(h)%", h >= 80 ? .green : .orange)
                }
                if let c = system.battery.cycleCount {
                    legend("循环", "\(c)", .secondary)
                }
                if let t = system.battery.temperatureC {
                    legend("温度", String(format: "%.0f°C", t), .secondary)
                }
                Spacer()
            }
        }
    }

    private var batteryIcon: String {
        if system.battery.charging { return "battery.100.bolt" }
        return system.battery.externalPower ? "powerplug" : "battery.100"
    }

    // MARK: 进程(含结束)

    private var processSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            sectionTitle("占用最高", icon: "list.number")
            ForEach(system.topProcesses) { p in
                HStack(spacing: 6) {
                    Text(p.name).font(.caption).lineLimit(1)
                    Spacer()
                    Text(ByteFormat.memory(p.memoryBytes))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 62, alignment: .trailing)
                    Text(String(format: "%.1f%%", p.cpuPercent))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                    Button {
                        procToKill = p
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("结束该进程")
                }
            }
        }
    }

    // MARK: 垃圾清理

    private var junkSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                sectionTitle("垃圾清理", icon: "trash")
                Spacer()
                if cleanup.scanning {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("扫描中…").font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    Button("重新扫描") { cleanup.scan() }
                        .controlSize(.mini)
                        .disabled(cleanup.cleaning)
                }
            }

            ForEach(cleanup.results) { result in
                Button {
                    cleanup.toggle(result.category)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: cleanup.selected.contains(result.category)
                              ? "checkmark.square.fill" : "square")
                            .foregroundStyle(cleanup.selected.contains(result.category) ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack {
                                Text(result.category.title).font(.caption.weight(.medium))
                                Spacer()
                                Text(ByteFormat.memory(UInt64(max(0, result.totalBytes))))
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Text(result.category.subtitle)
                                .font(.caption2).foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            HStack {
                if let r = cleanup.lastReport {
                    Text("已清理 \(ByteFormat.memory(UInt64(max(0, r.freedBytes))))" +
                         (r.failedCount > 0 ? " · \(r.failedCount) 项占用中跳过" : ""))
                        .font(.caption2).foregroundStyle(.green)
                } else {
                    Text("已选 \(ByteFormat.memory(UInt64(max(0, cleanup.selectedBytes))))")
                        .font(.caption2).foregroundStyle(.secondary)
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
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(cleanup.cleaning || cleanup.scanning || cleanup.selected.isEmpty || cleanup.selectedBytes == 0)
            }
        }
    }

    // MARK: 小组件

    private func sectionTitle(_ t: String, icon: String) -> some View {
        Label(t, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func legend(_ name: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(name).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(.caption2, design: .monospaced))
        }
    }
}

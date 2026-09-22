import SwiftUI

/// 内容量出来的高度 → 面板高度(NotchDock 接这个值调窗口)。
/// 面板高度不能写死:内容随主题、随额度窗口条数变,写死必然对不准,底下不是空一块就是被裁。
struct NotchContentHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 从刘海无缝长出的下拉面板形状:顶沿两角向内凹(融进菜单栏),底部两角圆润。
struct NotchShape: Shape {
    var topRadius: CGFloat = 7
    var bottomRadius: CGFloat = 24
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + topRadius, y: rect.minY + topRadius),
                       control: CGPoint(x: rect.minX + topRadius, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + topRadius, y: rect.maxY - bottomRadius))
        p.addQuadCurve(to: CGPoint(x: rect.minX + topRadius + bottomRadius, y: rect.maxY),
                       control: CGPoint(x: rect.minX + topRadius, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - topRadius - bottomRadius, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - topRadius, y: rect.maxY - bottomRadius),
                       control: CGPoint(x: rect.maxX - topRadius, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - topRadius, y: rect.minY + topRadius))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - topRadius, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// 刘海内容:收起=完全透明(平时干净,什么都不挂);展开=黑色刘海形状下拉面板。
/// 警告不在这里做持久展示——由 QuotaStore 在额度快用完时"短暂弹一下"(NotchController)。
/// 皮肤跟随全局主题:经典 = 原生灵动岛风;HUD = 影视包装 FUI 风;LED = 嵌在刘海里的一块健身器材显示屏。
struct NotchDockView: View {
    @ObservedObject var system: SystemMonitor
    @ObservedObject var usage: UsageStore
    @ObservedObject var quota: QuotaStore
    @ObservedObject var state: NotchDockState
    @ObservedObject private var settings = DisplaySettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let notchSize: CGSize

    private var hud: Bool { settings.isHUD }
    private var led: Bool { settings.isLED }
    /// 这块屏的主色:面板讲的是额度/用量,按配色规则归琥珀(具体读数仍按余量取色)
    private let screenTint = LED.amber

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { ctx in
            let now = ctx.date
            ZStack(alignment: .top) {
                if state.expanded {
                    panelBody(now: now)
                        .transition(.scale(scale: 0.9, anchor: .top).combined(with: .opacity))
                } else {
                    Color.clear   // 平时:完全隐藏,刘海保持干净
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onPreferenceChange(NotchContentHeight.self) { h in
                // 收起时内容不渲染,preference 会回落到 0——别拿 0 把量好的值冲掉,
                // 留着它下次展开就能一步到位,不用再从估算值跳一下。
                guard h > 1 else { return }
                Task { @MainActor in state.contentHeight = h }
            }
            .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
        }
    }

    /// 面板 = 毛玻璃垫底 + 主题色罩(半透明,让模糊透出来)+ 纹理(HUD 网格 / LED 点阵)+ 描边 + 内容。
    /// 底角:HUD 收小(12)贴合切角硬朗感;LED 用 20(iOS 味圆角,比经典 24 略收);经典保持原版 24。
    private func panelBody(now: Date) -> some View {
        let shape = NotchShape(bottomRadius: led ? 20 : (hud ? 12 : 24))
        return ZStack(alignment: .top) {
            HUDBlurView(material: .hudWindow)
            panelTint
            if hud && !settings.isPrism { HUDGridBackground(spacing: 22).opacity(0.6) }
            if led {
                // 屏底的常驻余晖:很淡的一层,只用来让"屏"看着是通电的。
                // 真正的底光是下面那盏跟着指针走的——固定钉一盏在中间,鼠标走到哪它都不动,
                // 既假又把下半块染成一片脏棕。
                RadialGradient(colors: [screenTint.opacity(0.05), .clear],
                               center: UnitPoint(x: 0.5, y: 0.62), startRadius: 0, endRadius: 240)
                LEDDotMatrix(tint: screenTint, pitch: 5, alpha: 0.10)
            }
        }
        .clipShape(shape)
        .overlay(shape.stroke(panelStroke, lineWidth: 1))
        // 底光跟着指针走,压在内容底下(它是"照明",不是覆盖层),所以在 expandedContent 之前叠。
        // LED 给得比 HUD 足:那块屏的质感就是靠底光托起来的。
        .mouseSpotlight(color: effectAccent, at: state.mouse,
                        radius: led ? 200 : 150, intensity: led ? 0.18 : 0.10, clip: shape)
        .overlay(alignment: .top) { expandedContent(now: now) }
        // 轮廓光:和弹窗/监控台同一套语言,跟着鼠标走。这儿不能用 trackingMouse
        // (非激活浮层的 hover 回调不可靠),位置由 NotchDock 的全局监听喂进 state.mouse。
        // 别改回自动循环:光会一路扫进菜单栏,和物理刘海割裂。经典主题不参与——无特效本来就是它的身份。
        .overlay {
            if let a = effectAccent {
                SweepBorder(shape: shape, color: a,
                            lineWidth: led ? 1.5 : 1,
                            drive: .follow(state.mouse))
                    .mask(sweepMask)
            }
        }
    }

    /// 轮廓光不进刘海那一横条。
    /// 面板顶沿那截边压在物理刘海/菜单栏底下,光扫上去就成了"从屏幕顶上冒出来的一道亮线",
    /// 和刘海本身对不上——割裂感就是这么来的。所以顶部一段渐隐,光只在面板自己的身体上走。
    private var sweepMask: some View {
        GeometryReader { geo in
            let fade = (notchSize.height + 10) / max(geo.size.height, 1)
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .white, location: min(0.999, fade)),
                .init(color: .white, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
    }

    /// 特效主色:与弹窗/监控台同源(HUD 青 / LED 琥珀);经典 = 无特效
    private var effectAccent: Color? {
        if led { return screenTint }
        if hud { return HUD.cyan }
        return nil
    }

    private var panelStroke: Color {
        if led { return screenTint.opacity(0.18) }
        return hud ? HUD.cyan.opacity(0.16) : Color.white.opacity(0.06)
    }

    /// HUD/LED:顶部纯黑融进物理刘海,往下过渡到各自的底色;经典:近黑半透罩(原生灵动岛就是半透的)。
    ///
    /// HUD/LED 的底**必须不透明**:之前底部是 .opacity(0.55),毛玻璃把桌面透上来,
    /// 下半块就糊成一片发灰发脏的东西——桌面越花越脏。这两套皮讲的都是"嵌在刘海里的一块屏",
    /// 屏就该是实的;要透光感,靠底光和点阵去做,不是靠让桌面漏上来。
    @ViewBuilder
    private var panelTint: some View {
        if led {
            LinearGradient(colors: [.black, .black, LED.bg], startPoint: .top, endPoint: .bottom)
        } else if hud {
            LinearGradient(colors: [.black, .black, HUD.bg], startPoint: .top, endPoint: .bottom)
        } else {
            LinearGradient(colors: [.black, Color(white: 0.045).opacity(0.82)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    // MARK: 展开(主角 = Claude 5 小时额度那类"即时会卡你"的窗口)

    private func expandedContent(now: Date) -> some View {
        let windows = QuotaRank.ranked(quota.quotas, now: now, activeTool: usage.activeTool)
        let hero = windows.first
        let rest = Array(windows.dropFirst())
        let health = ComputerHealth.evaluate(system)
        let mood = CompanionMood.resolve(
            activity: usage.recentActivity,
            quotaUsedPercent: hero?.1.effectiveUsed(now: now),
            quotaReset: hero?.1.hasReset(now: now) ?? true,
            health: companionHealth(health.level), now: now)
        return VStack(alignment: .leading, spacing: hud || led ? 10 : 12) {
            activityIdentity(now: now, mood: mood)
            if let hero { heroBlock(tool: hero.0, w: hero.1, now: now) } else { noQuotaHero }
            divider
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                spendCell("今日花费", "COST.TD", usage.today.totalCostUSD)
                spendCell("本月花费", "COST.MO", usage.thisMonth.totalCostUSD)
                Spacer()
            }
            if !rest.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(rest.enumerated()), id: \.offset) { _, item in
                        detailBar(tool: item.0, w: item.1, now: now)
                    }
                }
            }
            healthRow
        }
        .padding(.horizontal, 20)
        .padding(.top, notchSize.height + 8)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 量的必须是内容的**自然高度**:不 fixedSize 的话,面板高度反过来会把内容压/拉,
        // 量出来的就是面板自己的高度,永远自洽、永远不收敛。
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: NotchContentHeight.self, value: geo.size.height)
            }
        }
    }

    /// 第一层先回答“我刚才在用什么”。工具和模型来自最新本地会话事件;
    /// 超过 3 分钟就明说“最近使用”,不把历史快照冒充当前状态。
    @ViewBuilder
    private func activityIdentity(now: Date, mood: CompanionMoment) -> some View {
        if let activity = usage.recentActivity {
            let current = activity.isCurrent(now: now)
            let accent = current ? (led ? LED.green : (hud ? HUD.green : Color.green))
                                 : (led ? LED.amber : (hud ? HUD.amber : Color.orange))
            HStack(spacing: 9) {
                if led {
                    NotchLEDBreathDot(color: accent, size: 7, pulses: current)
                } else if hud {
                    HUDStatusDot(color: accent, size: 6, pulses: current)
                } else {
                    Circle().fill(accent).frame(width: 7, height: 7)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.statusLabel(now: now))
                        .font(led ? LED.mono(8) : (hud ? HUD.mono(8) : .system(size: 9)))
                        .foregroundStyle(.white.opacity(0.48))
                    Text("\(activity.tool == .claude ? "Claude" : "Codex") · \(ModelName.display(activity.model))")
                        .font(led ? LED.display(14, .bold)
                                  : (hud ? .system(size: 14, weight: .bold, design: .monospaced)
                                         : .system(size: 15, weight: .semibold, design: .rounded)))
                        .foregroundStyle(.white.opacity(0.94))
                        .lineLimit(1).minimumScaleFactor(0.78)
                    companionLine(mood)
                }
                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: 7) {
                Circle().fill(.white.opacity(0.25)).frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text("等待 AI 活动")
                        .font(.system(size: 9)).foregroundStyle(.white.opacity(0.45))
                    Text("模型待识别")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.72))
                    companionLine(mood)
                }
            }
        }
    }

    private func companionLine(_ mood: CompanionMoment) -> some View {
        HStack(spacing: 4) {
            Image(systemName: mood.icon)
                .font(.system(size: 8, weight: .semibold))
            Text(mood.text)
                .font(led ? LED.display(9, .medium)
                          : (hud ? HUD.mono(8, .medium)
                                 : .system(size: 10, weight: .medium, design: .rounded)))
                .lineLimit(1).minimumScaleFactor(0.82)
        }
        .foregroundStyle(companionColor(mood.tone).opacity(0.9))
        .padding(.top, 1)
    }

    @ViewBuilder
    private var divider: some View {
        if hud || led {
            let accent = led ? LED.amber : HUD.cyan
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                Rectangle().fill(accent.opacity(0.7)).frame(width: 40, height: 1)
                    .shadow(color: accent.opacity(0.5), radius: 2)
            }
        } else {
            Divider().overlay(.white.opacity(0.1))
        }
    }

    @ViewBuilder
    private func heroBlock(tool: ToolKind, w: QuotaWindow, now: Date) -> some View {
        if led { ledHeroBlock(tool: tool, w: w, now: now) }
        else { stdHeroBlock(tool: tool, w: w, now: now) }
    }

    /// LED 版主角:剩余时间走七段数码管。数字直接从秒数算——不去解析
    /// QuotaFormat.duration 的中文串(那太脆),话术层仍复用它保持逐字一致。
    private func ledHeroBlock(tool: ToolKind, w: QuotaWindow, now: Date) -> some View {
        let reset = w.hasReset(now: now)
        let c = barColor(w.effectiveUsed(now: now))
        let seg = Self.segmentDuration(w.remaining(now: now))
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(reset ? LED.green : c).frame(width: 6, height: 6)
                    .shadow(color: (reset ? LED.green : c).opacity(0.9), radius: 3)
                Text("\(tool.label) · \(w.kind.label)")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                Spacer()
                LEDCaption(text: reset ? "READY" : seg.unit, tint: LED.faint, size: 7)
            }
            if reset {
                Text("满额可用")
                    .font(LED.display(22, .bold))
                    .foregroundStyle(LED.green)
                    .shadow(color: LED.green.opacity(0.7), radius: 6)
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    SevenSegmentText(text: seg.digits, height: 30, color: c)
                    LEDCaption(text: w.usedPercent >= 85 ? "我替你盯着" : "还能痛快写",
                               tint: c.opacity(0.75), size: 7)
                        .padding(.bottom, 3)
                }
            }
            HStack(spacing: 8) {
                LEDGauge(ratio: reset ? 0 : w.effectiveUsed(now: now) / 100,
                         color: reset ? LED.green : c, height: 8)
                Text(reset ? "0%" : "\(Int(w.usedPercent))%")
                    .font(LED.mono(12, .semibold))
                    .foregroundStyle(.white.opacity(0.85)).frame(width: 38, alignment: .trailing)
            }
            if !reset {
                Text("\(QuotaFormat.resetClock(w.resetsAt)) 重置")
                    .font(LED.mono(9)).foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    /// 剩余秒数 → 七段数码管能显示的 "H:MM"(数码管只认数字/冒号/点),外加单位标注。
    static func segmentDuration(_ seconds: TimeInterval) -> (digits: String, unit: String) {
        let s = Int(max(0, seconds))
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return (String(format: "%d:%02d", d, h), "DAYS:HRS") }
        return (String(format: "%d:%02d", h, m), "HRS:MIN")
    }

    private func stdHeroBlock(tool: ToolKind, w: QuotaWindow, now: Date) -> some View {
        let reset = w.hasReset(now: now)
        let c = barColor(w.effectiveUsed(now: now))
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                if hud { Rectangle().fill(c).frame(width: 2, height: 9) }
                Text("\(tool.label) · \(w.kind.label)")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                if hud {
                    Text("QUOTA.LIVE")
                        .font(HUD.mono(7, .medium)).kerning(1.0).foregroundStyle(HUD.faint)
                }
            }
            Text(reset ? "满额可用" : "还能用 \(QuotaFormat.duration(w.remaining(now: now)))")
                .font(hud ? .system(size: 22, weight: .bold, design: .monospaced)
                          : .system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(reset ? (hud ? HUD.green : .green) : .white)
                .contentTransition(.numericText())
            HStack(spacing: 8) {
                if hud {
                    HUDGauge(ratio: reset ? 0 : w.effectiveUsed(now: now) / 100,
                             color: reset ? HUD.green : c, height: 8, segments: 30)
                } else {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.14))
                            Capsule().fill((reset ? Color.green : c).gradient)
                                .frame(width: max(4, geo.size.width * (w.effectiveUsed(now: now) / 100)))
                        }
                    }
                    .frame(height: 9)
                }
                Text(reset ? "0%" : "\(Int(w.usedPercent))%")
                    .font(hud ? HUD.mono(12, .semibold)
                              : .system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85)).frame(width: 38, alignment: .trailing)
            }
            if !reset {
                Text("\(QuotaFormat.resetClock(w.resetsAt)) 重置")
                    .font(hud ? HUD.mono(9) : .system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private var noQuotaHero: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("额度充足")
                .font(led ? LED.display(22, .bold)
                          : (hud ? .system(size: 22, weight: .bold, design: .monospaced)
                                 : .system(size: 22, weight: .bold, design: .rounded)))
                .foregroundStyle(led ? LED.green : (hud ? HUD.green : .green))
                .shadow(color: led ? LED.green.opacity(0.7) : .clear, radius: 6)
            Text("放心写,还早着呢").font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
        }
    }

    @ViewBuilder
    private func spendCell(_ title: String, _ code: String, _ usd: Double) -> some View {
        if led {
            // 花费=琥珀(配色规则),读数走数码管
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(title).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                    LEDCaption(text: code.replacingOccurrences(of: "COST.", with: ""),
                               tint: LED.faint, size: 7)
                }
                SevenSegmentText(text: DisplaySettings.shared.currencyStr(usd),
                                 height: 15, color: LED.amber)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                    if hud {
                        Text(code).font(HUD.mono(7, .medium)).kerning(0.8).foregroundStyle(HUD.faint)
                    }
                }
                Text(DisplaySettings.shared.currencyStr(usd))
                    .font(hud ? HUD.mono(16, .semibold)
                              : .system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    private func detailBar(tool: ToolKind, w: QuotaWindow, now: Date) -> some View {
        let used = w.effectiveUsed(now: now) / 100
        return HStack(spacing: 8) {
            Text("\(tool.label) · \(w.kind.shortLabel)")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                .frame(width: 116, alignment: .leading).lineLimit(1)
            if led {
                LEDGauge(ratio: used, color: barColor(w.effectiveUsed(now: now)), height: 4)
            } else if hud {
                HUDGauge(ratio: used, color: barColor(w.effectiveUsed(now: now)),
                         height: 4, segments: 20)
            } else {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.1))
                        Capsule().fill(barColor(w.effectiveUsed(now: now)))
                            .frame(width: max(3, geo.size.width * used))
                    }
                }
                .frame(height: 4)
            }
            Text(w.hasReset(now: now) ? "满" : QuotaFormat.duration(w.remaining(now: now)))
                .font(led ? LED.mono(8) : (hud ? HUD.mono(8) : .system(size: 9)))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 52, alignment: .trailing).lineLimit(1)
        }
    }

    private var healthRow: some View {
        let h = ComputerHealth.evaluate(system)
        return HStack(spacing: 7) {
            if led {
                NotchLEDBreathDot(color: ledHealthColor(h.level), size: 7, pulses: h.level != .good)
            } else if hud {
                HUDStatusDot(color: hudHealthColor(h.level), size: 6,
                             pulses: h.level != .good)
            } else {
                Circle().fill(h.color).frame(width: 7, height: 7)
            }
            Text(h.title).font(.system(size: 11, weight: h.level == .good ? .regular : .semibold))
                .foregroundStyle(.white.opacity(h.level == .good ? 0.5 : 0.85))
            Spacer()
        }
    }

    private func hudHealthColor(_ level: ComputerHealth.Level) -> Color {
        switch level {
        case .good: return HUD.green
        case .warn: return HUD.amber
        case .critical: return HUD.red
        }
    }

    private func ledHealthColor(_ level: ComputerHealth.Level) -> Color {
        switch level {
        case .good: return LED.green
        case .warn: return LED.amber
        case .critical: return LED.red
        }
    }

    private func companionHealth(_ level: ComputerHealth.Level) -> CompanionHealth {
        switch level {
        case .good: return .good
        case .warn: return .warn
        case .critical: return .critical
        }
    }

    private func companionColor(_ tone: CompanionTone) -> Color {
        switch tone {
        case .calm: return led ? LED.green : (hud ? HUD.green : .green)
        case .warm: return led ? LED.amber : (hud ? HUD.cyan : .orange)
        case .caution: return led ? LED.amber : (hud ? HUD.amber : .orange)
        case .urgent: return led ? LED.red : (hud ? HUD.red : .red)
        }
    }

    private func barColor(_ pct: Double) -> Color {
        if led { return pct >= 85 ? LED.red : (pct >= 60 ? LED.amber : LED.green) }
        if hud { return pct >= 85 ? HUD.red : (pct >= 60 ? HUD.amber : HUD.green) }
        return pct >= 85 ? .red : (pct >= 60 ? .orange : .green)
    }
}

/// 刘海 LED 皮肤的呼吸圆灯(HUD 的 HUDStatusDot 是方灯,两套语言不混用)
struct NotchLEDBreathDot: View {
    var color: Color = LED.green
    var size: CGFloat = 6
    var pulses: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.9), radius: size * 0.6)
            .shadow(color: color.opacity(0.4), radius: size * 1.4)
            .opacity(dimmed ? 0.35 : 1)
            .onAppear {
                guard pulses && !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    dimmed = true
                }
            }
    }
}

/// 额度主角排序。C 位 = **主力工具(当前在用 / 用得最多)的 5 小时窗口**——这是用户即时最关心的。
/// 优先级:主力5h(0) > 危险周额度≥90%(1) > 主力周(1) > 其它5h(2) > 其它(3);各档内已用%高优先;已重置排最后。
/// 主力工具:优先取"当前在用"(activeTool),否则取周额度用得最多的工具。
enum QuotaRank {
    static func ranked(_ quotas: [ToolQuota], now: Date, activeTool: ToolKind?) -> [(ToolKind, QuotaWindow)] {
        let all = quotas.flatMap { q in q.windows.map { (q.tool, $0) } }
        let active = all.filter { !$0.1.hasReset(now: now) }
        let reset = all.filter { $0.1.hasReset(now: now) }
        let primary = activeTool ?? primaryByWeekly(quotas)

        func score(_ x: (ToolKind, QuotaWindow)) -> (Int, Int) {
            let (tool, w) = x
            let isPrimary = (tool == primary)
            if isPrimary && w.kind == .fiveHour { return (0, 0) }
            if w.kind == .weekly && w.usedPercent >= 90 { return (1, 0) }   // 危险周额度仍要冒头
            if isPrimary { return (1, 1) }
            if w.kind == .fiveHour { return (2, 0) }
            return (3, 0)
        }
        let sortedActive = active.sorted { a, b in
            let (sa, sb) = (score(a), score(b))
            if sa.0 != sb.0 { return sa.0 < sb.0 }
            if sa.1 != sb.1 { return sa.1 < sb.1 }
            return a.1.usedPercent > b.1.usedPercent
        }
        return sortedActive + reset.sorted { $0.1.usedPercent > $1.1.usedPercent }
    }

    /// 用得最多的工具 = 周额度已用%最高者
    private static func primaryByWeekly(_ quotas: [ToolQuota]) -> ToolKind? {
        quotas.compactMap { q -> (ToolKind, Double)? in
            guard let wk = q.windows.first(where: { $0.kind == .weekly }) else { return nil }
            return (q.tool, wk.usedPercent)
        }.max(by: { $0.1 < $1.1 })?.0
    }
}

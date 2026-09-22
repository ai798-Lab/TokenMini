import SwiftUI

/// A full-width data hero. Only the window-stage boundary clips the foreground;
/// paper and signal bands terminate at that same edge without inset corner gaps.
struct PrismDashboardBanner: View {
    let total: String
    let scope: String
    let calls: String
    let input: String
    let output: String
    let cacheWrite: String
    let cacheRead: String

    var body: some View {
        PrismHeroStageLayout {
            GeometryReader { proxy in
                let layout = PrismHeroLayout(width: proxy.size.width)
                ZStack(alignment: .topLeading) {
                    Prism.bg
                    Text("TOKENMINI  /  用量总览")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1).foregroundStyle(Prism.secondary)
                        .padding(.leading, 20).padding(.top, 12)

                    backdrop(textWidth: layout.textWidth)
                        .frame(width: proxy.size.width, height: PrismHeroLayout.panelHeight)
                        .offset(y: layout.panelTop)

                    PrismBreakoutArtwork(width: layout.artworkWidth)
                        .offset(x: layout.artworkLeft, y: layout.artworkTop)
                }
                .frame(width: proxy.size.width, height: layout.stageHeight, alignment: .topLeading)
                .clipped()
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func backdrop(textWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Prism.panel
            Rectangle().fill(Prism.silver).frame(height: 108)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(scope) · Token")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Prism.bg.opacity(0.72))
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(total)
                    .font(.system(size: 62, weight: .heavy)).tracking(-2)
                    .monospacedDigit().foregroundStyle(Prism.bg)
                    .lineLimit(1).minimumScaleFactor(0.4)
                    .contentTransition(.numericText())
                    .frame(height: 74, alignment: .leading)
            }
            .frame(width: textWidth, alignment: .leading)
            .padding(.leading, 20).padding(.top, 9)

            VStack(alignment: .leading, spacing: 10) {
                Text(calls).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Prism.secondary)
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                    GridRow {
                        metric("输入", value: input)
                        metric("输出", value: output)
                    }
                    GridRow {
                        metric("缓存写", value: cacheWrite)
                        metric("缓存读", value: cacheRead)
                    }
                }
            }
            .frame(width: textWidth, alignment: .leading)
            .padding(.leading, 20).padding(.top, 120)
        }
        .overlay(alignment: .bottomLeading) {
            HStack {
                Text("总量 = 输入 + 输出 + 缓存写 + 缓存读")
                    .font(.system(size: 9, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Prism.bg)
            .padding(.horizontal, 20).frame(height: 22)
            .background(Prism.mint)
        }
        .allowsHitTesting(false)
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 9)).foregroundStyle(Prism.secondary)
            Text(value).font(.system(size: 16, weight: .bold)).monospacedDigit()
                .foregroundStyle(Prism.silver).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PrismHeroLayout {
    static let panelHeight: CGFloat = 260
    let width: CGFloat
    var stageHeight: CGFloat { min(440, max(342, width / 2.8)) }
    var panelTop: CGFloat { (stageHeight - Self.panelHeight) / 2 }
    var textWidth: CGFloat { width * 0.42 - 32 }
    var artworkWidth: CGFloat { stageHeight * 2.32 }
    var artworkHeight: CGFloat { artworkWidth * 941 / 1672 }
    var artworkLeft: CGFloat { width * 0.44 }
    var artworkTop: CGFloat { (stageHeight - artworkHeight) / 2 }
}

/// Reserve the full silhouette height in the scroll layout, including at narrow widths.
private struct PrismHeroStageLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 760
        return CGSize(width: width, height: PrismHeroLayout(width: width).stageHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for view in subviews {
            view.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
        }
    }
}

/// Shared by the dashboard and menu-bar panel. The image itself has no card mask.
struct PrismBreakoutArtwork: View {
    let width: CGFloat
    var body: some View {
        if let image = Prism.core {
            Image(nsImage: image).resizable().scaledToFit()
                .frame(width: width, height: width * 941 / 1672)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// Compact composition for the 360pt menu panel, with a protected text column.
struct PrismTokenHero: View {
    let value: String
    private let stageHeight: CGFloat = 178
    private let panelHeight: CGFloat = 122

    var body: some View {
        GeometryReader { proxy in
            let panelTop = (stageHeight - panelHeight) / 2
            let artworkWidth: CGFloat = 410
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    Prism.panel
                    Rectangle().fill(Prism.silver).frame(height: 32)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("TODAY / 今日 Token")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Prism.bg)
                            .frame(height: 32)
                        Text(value)
                            .font(.system(size: 34, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(Prism.silver)
                            .contentTransition(.numericText())
                            .lineLimit(1).minimumScaleFactor(0.4)
                            .frame(width: 130, height: 54, alignment: .leading)
                        Text("输入、输出与缓存的合计")
                            .font(.system(size: 9)).foregroundStyle(Prism.secondary)
                            .lineLimit(1)
                    }
                    .padding(.leading, 14)
                }
                .frame(width: proxy.size.width, height: panelHeight)
                .overlay(alignment: .bottom) { Rectangle().fill(Prism.line).frame(height: 1) }
                .offset(y: panelTop)

                PrismBreakoutArtwork(width: artworkWidth)
                    // Text ends at 14 + 130pt; keep an 8pt gap before the beam.
                    .offset(x: 152, y: (stageHeight - artworkWidth * 941 / 1672) / 2)
            }
            .frame(width: proxy.size.width, height: stageHeight, alignment: .topLeading)
            .clipped()
        }
        .frame(height: stageHeight)
    }
}

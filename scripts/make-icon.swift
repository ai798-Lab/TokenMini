import AppKit
import SwiftUI
import WebKit

// 从 `logo icon.svg` 生成 macOS 应用图标 iconset。
//
// 设计源文件按苹果规范画:1024×1024 画布、满画布出血、**不带圆角**、logo 在中间 824 安全区内。
// 圆角/留白由本脚本套,设计稿不要自己画——画了这里还得切掉。
//
// 苹果图标网格(Big Sur ~ Tahoe 26 未变,已用 Safari.app 图标实测拟合印证):
//   画布 1024;主体 824×824 居中(四边留 100,留给系统阴影);圆角 185.4(= 824 的 22.5%);
//   圆角是 squircle(连续曲率),不是普通圆角。
// 1024 的设计整体**缩放**进 824 主体(不是裁切),这样设计稿的构图比例完整保留。
//
// SVG 交给 WebKit 渲染:设计稿里的 radial 渐变 / mix-blend-mode / feMorphology 内阴影
// 只有真渲染引擎认得,手搓 path 解析器做不到。

let CANVAS: CGFloat = 1024
let BODY: CGFloat = 824             // 苹果:主体 824 居中
let RADIUS: CGFloat = 185.4         // 苹果:圆角 185.4(= 824 的 22.5%)
let RENDER: CGFloat = 2048          // SVG 先渲染到 2x,再缩到各目标尺寸,保证小尺寸锐利

// MARK: - WebKit 渲染 SVG

final class SVGRenderer: NSObject, WKNavigationDelegate {
    private var result: NSBitmapImageRep?
    private var finished = false
    private var webView: WKWebView!

    func render(svgFile: String) -> NSBitmapImageRep? {
        guard let svg = try? String(contentsOfFile: svgFile, encoding: .utf8) else {
            FileHandle.standardError.write("读不到 \(svgFile)\n".data(using: .utf8)!)
            exit(1)
        }
        let side = Int(RENDER)
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: RENDER, height: RENDER),
                            configuration: WKWebViewConfiguration())
        webView.navigationDelegate = self
        // 背景透明 + SVG 撑满,截图尺寸就等于 RENDER
        let html = """
        <html><head><style>
        html,body{margin:0;padding:0;background:transparent;}
        svg{display:block;width:\(side)px;height:\(side)px;}
        </style></head><body>\(svg)</body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)

        let deadline = Date().addingTimeInterval(30)
        while !finished && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        return result
    }

    func webView(_ wv: WKWebView, didFinish nav: WKNavigation!) {
        let cfg = WKSnapshotConfiguration()
        cfg.rect = NSRect(x: 0, y: 0, width: RENDER, height: RENDER)
        cfg.snapshotWidth = NSNumber(value: Int(RENDER))
        // 渐变/滤镜合成完再截,否则可能截到半成品
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            wv.takeSnapshot(with: cfg) { img, err in
                defer { self?.finished = true }
                guard let img, let tiff = img.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff) else {
                    FileHandle.standardError.write("SVG 截图失败: \(String(describing: err))\n".data(using: .utf8)!)
                    return
                }
                self?.result = rep
            }
        }
    }
}

// MARK: - 合成图标

/// 苹果 squircle。必须用 SwiftUI 连续圆角——它就是系统原厂那条曲线。
/// 别换成 NSBezierPath(roundedRect:xRadius:yRadius:),那是普通圆角(circular),
/// 曲率不连续,和系统图标对不上(已用 Safari.app 图标拟合验证:824 主体 + 半径 188±2 continuous)。
@MainActor
func squirclePath(in rect: CGRect, radius: CGFloat) -> CGPath {
    RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect).cgPath
}

@MainActor
func composeIcon(size: CGFloat, artwork: NSBitmapImageRep) -> NSBitmapImageRep {
    let px = Int(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gc
    gc.imageInterpolation = .high
    let ctx = gc.cgContext

    let s = size / CANVAS
    ctx.scaleBy(x: s, y: s)

    let inset = (CANVAS - BODY) / 2                 // 100
    let body = CGRect(x: inset, y: inset, width: BODY, height: BODY)

    // 主体裁成 squircle,1024 的设计整体缩放填满它
    ctx.saveGState()
    ctx.addPath(squirclePath(in: body, radius: RADIUS))
    ctx.clip()
    artwork.draw(in: NSRect(x: body.origin.x, y: body.origin.y,
                            width: body.width, height: body.height))
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - 导出

let repoRoot = FileManager.default.currentDirectoryPath
let svgFile = "\(repoRoot)/logo icon.svg"
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./AppIcon.iconset"

let specs: [(String, CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

MainActor.assumeIsolated {
    // 用局部变量持住 renderer:直接 SVGRenderer().render(…) 的话,
    // 编译器认为临时对象已释放、闭包里的 weak self 恒为 nil(实际能跑通是因为 render 同步阻塞)
    let renderer = SVGRenderer()
    guard let artwork = renderer.render(svgFile: svgFile) else {
        FileHandle.standardError.write("渲染 \(svgFile) 失败\n".data(using: .utf8)!)
        exit(1)
    }
    print("渲染设计稿: \(artwork.pixelsWide)x\(artwork.pixelsHigh) <- \(svgFile)")

    try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
    for (name, sz) in specs {
        let rep = composeIcon(size: sz, artwork: artwork)
        guard let data = rep.representation(using: .png, properties: [:]) else { continue }
        try? data.write(to: URL(fileURLWithPath: "\(out)/\(name)"))
    }
    // 单独出一张 1024 预览,方便肉眼验收
    if let d = composeIcon(size: 1024, artwork: artwork).representation(using: .png, properties: [:]) {
        try? d.write(to: URL(fileURLWithPath: "\(out)/../icon-preview-1024.png"))
    }
    print("iconset -> \(out)")
}

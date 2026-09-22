import SwiftUI
import AppKit

/// Cache the vector masters, letting AppKit rasterize at the destination display's scale.
/// Loading a PNG by URL does not attach its @2x sibling. Each size also has its own
/// optical master so the header never enlarges the 16-point menu-bar artwork.
enum BrandImages {
    static let menuBar = load("MenuBarMark", pointSize: 16)
    static let header = load("HeaderMark", pointSize: 20)

    private static func load(_ name: String, pointSize: CGFloat) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "pdf"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: pointSize, height: pointSize)
        image.isTemplate = true
        return image
    }
}

/// All native headers share the 20-point optically corrected TokenMini mark.
struct BrandMark: View {
    var body: some View {
        if let image = BrandImages.header {
            Image(nsImage: image)
                .renderingMode(.template)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
        }
    }
}

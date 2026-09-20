import SwiftUI
import AppKit

/// All native headers share the same optically corrected TokenMini mark.
struct BrandMark: View {
    private static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "MenuBarMark", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
        }
    }
}

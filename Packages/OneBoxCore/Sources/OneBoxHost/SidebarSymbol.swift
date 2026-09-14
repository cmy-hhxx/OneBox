import SwiftUI

/// Match BoardUI's icon viewport rather than SF Symbols' varying font metrics.
struct SidebarSymbol: View {
    let name: String
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: name)
            .resizable()
            .scaledToFit()
            .symbolRenderingMode(.monochrome)
            .fontWeight(.regular)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

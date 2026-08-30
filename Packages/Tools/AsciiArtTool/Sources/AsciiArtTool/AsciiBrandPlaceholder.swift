import OneBoxDesignSystem
import SwiftUI

@MainActor
struct AsciiBrandPlaceholder: View {
    let image: CGImage?

    @Environment(\.designPalette) private var palette

    var body: some View {
        ZStack {
            palette.background

            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
            }
        }
    }
}

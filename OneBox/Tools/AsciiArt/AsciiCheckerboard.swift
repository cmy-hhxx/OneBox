import OneBoxDesignSystem
import SwiftUI

@MainActor
struct AsciiCheckerboard: View {
    @Environment(\.designPalette) private var palette

    var body: some View {
        Canvas { context, size in
            let tile = DesignMetrics.space12
            let columns = Int(ceil(size.width / tile))
            let rows = Int(ceil(size.height / tile))
            for row in 0..<rows {
                for column in 0..<columns {
                    let color =
                        (row + column).isMultiple(of: 2)
                        ? palette.surface
                        : palette.surfaceElevated
                    context.fill(
                        Path(
                            CGRect(
                                x: Double(column) * tile,
                                y: Double(row) * tile,
                                width: tile,
                                height: tile
                            )
                        ),
                        with: .color(color)
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }
}

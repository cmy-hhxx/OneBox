import OneBoxDesignSystem
import SwiftUI

struct OneBoxBrandMark: View {
    @Environment(\.designPalette) private var palette

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 24
            let outer = CGRect(
                x: 2 * scale,
                y: 2.5 * scale,
                width: 23.5 * scale,
                height: 23.5 * scale
            )
            let core = CGRect(
                x: 6.2 * scale,
                y: 9.3 * scale,
                width: 15.2 * scale,
                height: 12.4 * scale
            )
            let leftEye = CGRect(
                x: 9.1 * scale,
                y: 13 * scale,
                width: 1.4 * scale,
                height: 3.2 * scale
            )
            let rightEye = CGRect(
                x: 17 * scale,
                y: 13 * scale,
                width: 1.4 * scale,
                height: 3.2 * scale
            )
            let mouth = CGRect(
                x: 12.9 * scale,
                y: 17.1 * scale,
                width: 1.9 * scale,
                height: 1.2 * scale
            )

            context.fill(
                Path(roundedRect: outer, cornerRadius: 7 * scale),
                with: .color(palette.brandMarkHost)
            )
            context.fill(
                Path(roundedRect: core, cornerRadius: 4.2 * scale),
                with: .color(palette.brandMarkCore)
            )
            for facialMark in [leftEye, rightEye, mouth] {
                context.fill(
                    Path(
                        roundedRect: facialMark,
                        cornerRadius: min(facialMark.width, facialMark.height) / 2
                    ),
                    with: .color(palette.brandMarkHost)
                )
            }
        }
        .frame(
            width: DesignMetrics.brandMarkSize,
            height: DesignMetrics.brandMarkSize
        )
        .clipped()
        .accessibilityHidden(true)
    }
}

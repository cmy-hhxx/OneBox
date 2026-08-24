import SwiftUI

public struct ToolPlaceholderView: View {
    @Environment(\.designPalette) private var palette

    public init() {}

    public var body: some View {
        Text("待接入")
            .font(DesignTypography.body)
            .foregroundStyle(palette.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 240, alignment: .center)
    }
}

import OneBoxDesignSystem
import OneBoxHost
import OneBoxPlatform
import SwiftUI

@main
struct OneBoxApp: App {
    private let catalog = AppComposition.makeCatalog()
    private let previewColorScheme: ColorScheme?
    private let forcedPreviewWindowSize: CGSize?
    private let initialWidth: CGFloat
    private let initialHeight: CGFloat

    init() {
        #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            previewColorScheme = arguments.contains("--ui-dark") ? .dark : nil
            if arguments.contains("--ui-minimum") {
                forcedPreviewWindowSize = DesignMetrics.minimumWindowSize
            } else if arguments.contains("--ui-default") {
                forcedPreviewWindowSize = DesignMetrics.defaultWindowSize
            } else {
                forcedPreviewWindowSize = nil
            }
            let initialSize = forcedPreviewWindowSize ?? DesignMetrics.defaultWindowSize
            initialWidth = initialSize.width
            initialHeight = initialSize.height
        #else
            previewColorScheme = nil
            forcedPreviewWindowSize = nil
            initialWidth = DesignMetrics.defaultWindowSize.width
            initialHeight = DesignMetrics.defaultWindowSize.height
        #endif
    }

    var body: some Scene {
        Window("OneBox", id: "main") {
            HostView(catalog: catalog)
                .background {
                    WindowAspectRatioConfigurator(
                        aspectRatio: DesignMetrics.windowAspectRatio,
                        minimumWindowSize: DesignMetrics.minimumWindowSize,
                        forcedWindowSize: forcedPreviewWindowSize
                    )
                }
                .preferredColorScheme(previewColorScheme ?? .light)
        }
        .defaultSize(width: initialWidth, height: initialHeight)
        .windowStyle(.hiddenTitleBar)
    }
}

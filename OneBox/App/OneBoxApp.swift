import OneBoxDesignSystem
import OneBoxHost
import SwiftUI

@main
struct OneBoxApp: App {
    @NSApplicationDelegateAdaptor(OneBoxApplicationDelegate.self)
    private var applicationDelegate

    private let launchPerformanceTrace = AppLaunchPerformanceTrace()
    private let catalog = AppComposition.makeCatalog()
    private let previewColorScheme: ColorScheme?
    private let forcedPreviewWindowSize: CGSize?
    private let forcesReduceMotionForUITesting: Bool
    private let initialWidth: CGFloat
    private let initialHeight: CGFloat

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        forcesReduceMotionForUITesting =
            AppComposition.UITestingConfiguration.forcesReduceMotion(arguments: arguments)
        #if DEBUG
            previewColorScheme = arguments.contains("--ui-dark") ? .dark : nil
        #else
            previewColorScheme = nil
        #endif
        forcedPreviewWindowSize = AppComposition.UITestingConfiguration.forcedWindowSize(
            arguments: arguments
        )
        let initialSize = forcedPreviewWindowSize ?? DesignMetrics.defaultWindowSize
        initialWidth = initialSize.width
        initialHeight = initialSize.height
    }

    var body: some Scene {
        Window("OneBox", id: "main") {
            HostView(
                catalog: catalog,
                onInitialContentReady: launchPerformanceTrace.finish
            )
            .onAppear {
                applicationDelegate.configureApplicationTermination {
                    await catalog.prepareForApplicationTermination()
                }
            }
            .background {
                WindowGeometryConfigurator(
                    minimumWindowSize: DesignMetrics.minimumWindowSize,
                    forcedWindowSize: forcedPreviewWindowSize
                )
            }
            .preferredColorScheme(previewColorScheme ?? .light)
            .environment(
                \.oneBoxAccessibilityReduceMotionOverride,
                forcesReduceMotionForUITesting ? true : nil
            )
        }
        .defaultSize(width: initialWidth, height: initialHeight)
        .windowStyle(.hiddenTitleBar)
    }
}

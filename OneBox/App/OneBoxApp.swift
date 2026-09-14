import OneBoxDesignSystem
import OneBoxHost
import OneBoxRuntime
import SwiftUI

@main
struct OneBoxApp: App {
    @NSApplicationDelegateAdaptor(OneBoxApplicationDelegate.self)
    private var applicationDelegate

    private let launchPerformanceTrace = AppLaunchPerformanceTrace()
    private let catalog: ToolCatalog
    private let debugLogStore: DebugLogStore
    @State private var isDiagnosticsPresented = false
    @Environment(\.openWindow) private var openWindow
    private let previewColorScheme: ColorScheme?
    private let forcedPreviewWindowSize: CGSize?
    private let forcesReduceMotionForUITesting: Bool
    private let initialWidth: CGFloat
    private let initialHeight: CGFloat

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let isUITesting = arguments.contains("--ui-testing")
        let logs = DebugLogStore(
            isEnabled: arguments.contains("--debug-mode")
                || (!isUITesting && UserDefaults.standard.bool(forKey: "onebox.debugMode")),
            onEnabledChanged: { enabled in
                if !isUITesting { UserDefaults.standard.set(enabled, forKey: "onebox.debugMode") }
            }
        )
        debugLogStore = logs
        catalog = AppComposition.makeCatalog(debugLogStore: logs)
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
                onInitialContentReady: launchPerformanceTrace.finish,
                debugLogStore: debugLogStore,
                isDiagnosticsPresented: $isDiagnosticsPresented,
                copyDiagnosticsText: { text in
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            )
            .onAppear {
                applicationDelegate.configureApplicationTermination {
                    await catalog.prepareForApplicationTermination()
                }
            }
            .onDisappear { isDiagnosticsPresented = false }
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
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button("调试日志") {
                    openWindow(id: "main")
                    isDiagnosticsPresented.toggle()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }

    }
}

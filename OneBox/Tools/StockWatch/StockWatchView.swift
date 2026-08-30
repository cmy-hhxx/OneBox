import Accessibility
import OneBoxDesignSystem
import SwiftUI

@MainActor
struct StockWatchView: View {
    @StateObject private var bootstrap: StockWatchBootstrap
    private let platform: any StockWatchPlatformClient
    private let session: StockWatchModuleSession

    @Environment(\.designPalette) private var palette
    @State private var startupPathActionMessage: String?

    init(
        platform: any StockWatchPlatformClient,
        lifecycleCoordinator: StockWatchLifecycleCoordinator,
        session: StockWatchModuleSession
    ) {
        self.platform = platform
        self.session = session
        _bootstrap = StateObject(
            wrappedValue: StockWatchBootstrap(
                platform: platform,
                lifecycleCoordinator: lifecycleCoordinator
            )
        )
    }

    var body: some View {
        Group {
            if let run = bootstrap.mountedRun {
                StockWatchWorkspaceView(
                    store: run.store,
                    preferences: run.preferences,
                    copyText: platform.copyText,
                    revealDirectory: platform.revealDirectory
                )
            } else if let failure = bootstrap.failure {
                startupFailure(failure)
            } else {
                startupProgress
            }
        }
        .task {
            await session.runVisibleLifecycle {
                await bootstrap.run()
            }
        }
    }

    private var startupProgress: some View {
        VStack(spacing: DesignMetrics.space12) {
            ProgressView()
                .controlSize(.regular)
            Text("正在打开本地行情数据…")
                .font(DesignTypography.body)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func startupFailure(_ failure: StockWatchStartupFailure) -> some View {
        ContentUnavailableView {
            Label("无法打开股票看盘数据", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text(failure.message)
                .font(DesignTypography.body)
        } actions: {
            Button("重试", systemImage: "arrow.clockwise") {
                bootstrap.requestRetry()
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.accent)
            .disabled(bootstrap.isStarting)

            if !failure.databasePath.isEmpty {
                Button("复制数据库路径", systemImage: "doc.on.doc") {
                    copyDatabasePath(failure.databasePath)
                }
                .buttonStyle(.bordered)

                Button("在 Finder 中显示目录", systemImage: "folder") {
                    revealDatabaseDirectory(path: failure.databasePath)
                }
                .buttonStyle(.bordered)
            }

            if let startupPathActionMessage {
                Text(startupPathActionMessage)
                    .font(DesignTypography.metadata)
                    .foregroundStyle(
                        startupPathActionMessage.hasPrefix("已")
                            ? palette.positive
                            : palette.negative
                    )
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .foregroundStyle(palette.textPrimary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func copyDatabasePath(_ path: String) {
        publishStartupPathFeedback(
            platform.copyText(path)
                ? "已复制数据库路径"
                : "复制数据库路径失败"
        )
    }

    private func revealDatabaseDirectory(path: String) {
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        publishStartupPathFeedback(
            platform.revealDirectory(directory)
                ? "已在 Finder 中显示目录"
                : "无法在 Finder 中显示目录"
        )
    }

    private func publishStartupPathFeedback(_ message: String) {
        startupPathActionMessage = message
        if !message.hasPrefix("已") {
            AccessibilityNotification.Announcement(message).post()
        }
    }
}

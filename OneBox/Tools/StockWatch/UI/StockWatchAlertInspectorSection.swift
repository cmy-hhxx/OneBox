import OneBoxDesignSystem
import SwiftUI

enum AlertThresholdPresentation {
    static func valueText(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }
}

@MainActor
struct StockWatchAlertInspectorSection: View {
    @ObservedObject var store: MonitorStore
    @Bindable var preferences: StockWatchPreferences

    @Environment(\.designPalette) private var palette
    @State private var isGeneratingTargets = false
    @State private var targetGenerationMessage: String?
    @State private var targetGenerationRequest = 0

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.space12) {
            Text("价格提醒")
                .font(DesignTypography.sectionTitle)
                .accessibilityAddTraits(.isHeader)

            Toggle("启用价格提醒", isOn: alertConfigurationBinding(\.isEnabled))
                .toggleStyle(.switch)

            Picker("提醒依据", selection: alertConfigurationBinding(\.basis)) {
                ForEach(AlertBasis.allCases) { basis in
                    Text(basis.displayName).tag(basis)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("提醒依据")

            VStack(alignment: .leading, spacing: DesignMetrics.space12) {
                thresholdControl(
                    title: store.alertConfiguration.basis == .percentage
                        ? "上涨超过"
                        : "目标上涨幅度",
                    systemImage: "arrow.up.right",
                    value: alertConfigurationBinding(\.risingThreshold)
                )
                thresholdControl(
                    title: store.alertConfiguration.basis == .percentage
                        ? "下跌超过"
                        : "目标下跌幅度",
                    systemImage: "arrow.down.right",
                    value: alertConfigurationBinding(\.fallingThreshold)
                )
            }
            .disabled(!store.alertConfiguration.isEnabled)

            Button(action: requestTargetGeneration) {
                if isGeneratingTargets {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("按现价生成目标", systemImage: "scope")
                }
            }
            .buttonStyle(.bordered)
            .disabled(
                isGeneratingTargets
                    || !store.alertConfiguration.isEnabled
                    || store.instruments.isEmpty
            )

            if let targetGenerationMessage {
                Text(targetGenerationMessage)
                    .font(DesignTypography.metadata)
                    .foregroundStyle(
                        targetGenerationMessage.hasPrefix("已")
                            ? palette.textSecondary
                            : palette.negative
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }

            soundControl(
                title: "上涨提示音",
                isOn: $preferences.bullSoundEnabled,
                direction: .rising
            )
            soundControl(
                title: "下跌提示音",
                isOn: $preferences.bearSoundEnabled,
                direction: .falling
            )
        }
        .task(id: targetGenerationRequest) {
            guard targetGenerationRequest > 0 else { return }
            await generateTargetsFromCurrentPrices()
        }
    }

    private func thresholdControl(
        title: String,
        systemImage: String,
        value: Binding<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignMetrics.space4) {
            HStack(spacing: DesignMetrics.space8) {
                Label(title, systemImage: systemImage)
                    .font(DesignTypography.metadata)
                Spacer(minLength: 0)
                Text(AlertThresholdPresentation.valueText(value.wrappedValue))
                    .font(DesignTypography.metadata)
                    .monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
            }

            Slider(value: value, in: 0.5...15, step: 0.5)
                .tint(palette.accent)
                .controlSize(.small)
                .accessibilityLabel(title)
                .accessibilityValue(AlertThresholdPresentation.valueText(value.wrappedValue))
        }
    }

    private func soundControl(
        title: String,
        isOn: Binding<Bool>,
        direction: AlertDirection
    ) -> some View {
        HStack(spacing: DesignMetrics.space8) {
            Toggle(title, isOn: isOn)
                .toggleStyle(.switch)

            Spacer(minLength: 0)

            Button("预览 \(title)", systemImage: "speaker.wave.2") {
                store.testAlert(direction)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("预览 \(title)")
            .accessibilityLabel("预览 \(title)")
        }
    }

    private func alertConfigurationBinding<Value>(
        _ keyPath: WritableKeyPath<AlertConfiguration, Value>
    ) -> Binding<Value> {
        Binding(
            get: { store.alertConfiguration[keyPath: keyPath] },
            set: { value in
                var configuration = store.alertConfiguration
                configuration[keyPath: keyPath] = value
                store.updateAlertConfiguration(configuration)
            }
        )
    }

    private func requestTargetGeneration() {
        guard !isGeneratingTargets else { return }
        isGeneratingTargets = true
        targetGenerationMessage = nil
        targetGenerationRequest += 1
    }

    private func generateTargetsFromCurrentPrices() async {
        let count = await store.generatePriceTargetsFromCurrentQuotes()
        guard !Task.isCancelled else { return }
        guard let count else {
            isGeneratingTargets = false
            return
        }
        targetGenerationMessage =
            count > 0
            ? "已按现价为 \(count) 个标的生成目标"
            : "没有可用现价，请检查行情状态后重试"
        isGeneratingTargets = false
    }
}

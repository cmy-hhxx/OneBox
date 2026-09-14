import Accessibility
import OneBoxDesignSystem
import SwiftUI

@MainActor
struct AlertBannerView: View {
    let alert: AlertEvent
    let setDismissalPaused: (Bool) -> Void
    let dismiss: () -> Void
    private let announce: @MainActor (String) -> Void

    @Environment(\.designPalette) private var palette
    @FocusState private var focusedElement: AlertBannerFocusTarget?
    @State private var isHovering = false

    init(
        alert: AlertEvent,
        setDismissalPaused: @escaping (Bool) -> Void,
        dismiss: @escaping () -> Void,
        announce: @escaping @MainActor (String) -> Void = { message in
            AccessibilityNotification.Announcement(message).post()
        }
    ) {
        self.alert = alert
        self.setDismissalPaused = setDismissalPaused
        self.dismiss = dismiss
        self.announce = announce
    }

    private var isRising: Bool {
        alert.direction == .rising
    }

    private var accentColor: Color {
        alert.instrument.market
            .colorRole(isRising: isRising)
            .color(in: palette)
    }

    var body: some View {
        HStack(alignment: .top, spacing: DesignMetrics.space12) {
            alertSummary

            Spacer(minLength: 0)

            Button("关闭提醒", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(ToolCloseButtonStyle())
                .focused($focusedElement, equals: .descendantControl)
                .accessibilityLabel("关闭提醒")
        }
        .padding(DesignMetrics.space16)
        .frame(maxWidth: 400, alignment: .leading)
        .background(palette.surface)
        .clipShape(.rect(cornerRadius: DesignMetrics.space16))
        .overlay {
            RoundedRectangle(cornerRadius: DesignMetrics.space16)
                .strokeBorder(
                    focusedElement == nil ? palette.border : palette.accent,
                    lineWidth: focusedElement == nil ? 1 : 2
                )
        }
        .shadow(color: palette.dropdownContactShadow, radius: 1, x: 0, y: 1)
        .shadow(color: palette.dropdownAmbientShadow, radius: 4, x: 0, y: 4)
        .contentShape(.rect)
        .focusable()
        .focused($focusedElement, equals: .banner)
        .onHover { hovering in
            isHovering = hovering
            updatePauseState()
        }
        .onChange(of: focusedElement) { _, _ in
            updatePauseState()
        }
        .onAppear(perform: announceCurrentAlert)
        .onChange(of: alert.id) { _, _ in
            announceCurrentAlert()
        }
        .onDisappear {
            setDismissalPaused(false)
        }
    }

    private var alertSummary: some View {
        HStack(alignment: .top, spacing: DesignMetrics.space12) {
            Image(
                systemName: isRising ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill"
            )
            .font(DesignTypography.metric)
            .foregroundStyle(accentColor)
            .frame(width: 40, height: 40)
            .background(palette.surfaceElevated, in: .circle)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DesignMetrics.space4) {
                HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.space8) {
                    Text(isRising ? "上涨提醒" : "下跌提醒")
                        .font(DesignTypography.bodyMedium)
                        .foregroundStyle(palette.textPrimary)
                    Text(alert.triggeredAt.formatted(date: .omitted, time: .shortened))
                        .font(DesignTypography.metadata)
                        .monospacedDigit()
                        .foregroundStyle(palette.textSecondary)
                }

                Text(alertDetail)
                    .font(DesignTypography.body)
                    .monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityAnnouncement)
        .accessibilityHint("将指针停留或通过键盘聚焦时，提醒会保持显示")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var alertAnnouncement: AlertBannerAnnouncement {
        AlertBannerAnnouncement(alert: alert)
    }

    private var alertDetail: String {
        alertAnnouncement.detail
    }

    private var accessibilityAnnouncement: String {
        alertAnnouncement.message
    }

    private func announceCurrentAlert() {
        alertAnnouncement.post(using: announce)
    }

    private func updatePauseState() {
        setDismissalPaused(
            AlertBannerDismissalState(
                isHovering: isHovering,
                focusedElement: focusedElement
            ).isPaused
        )
    }
}

struct AlertBannerAnnouncement {
    let alert: AlertEvent

    var detail: String {
        guard alert.basis == .targetPrice, let targetPrice = alert.targetPrice else {
            return "\(alert.instrument.name) · \(formattedPercent)"
        }
        return String(
            format: tr("%@ · 现价 %@%.2f · 目标 %@%.2f"),
            alert.instrument.name,
            alert.instrument.market.currencySymbol,
            alert.lastPrice,
            alert.instrument.market.currencySymbol,
            targetPrice
        )
    }

    var message: String {
        "\(alert.direction == .rising ? tr("上涨提醒") : tr("下跌提醒"))，\(detail)，\(alert.triggeredAt.formatted(date: .omitted, time: .shortened))"
    }

    func post(using announce: (String) -> Void) {
        announce(message)
    }

    private var formattedPercent: String {
        String(
            format: "%@%.2f%%",
            alert.changePercent >= 0 ? "+" : "",
            alert.changePercent
        )
    }
}

enum AlertBannerFocusTarget: Hashable {
    case banner
    case descendantControl
}

struct AlertBannerDismissalState: Equatable {
    let isHovering: Bool
    let focusedElement: AlertBannerFocusTarget?

    var isPaused: Bool {
        isHovering || focusedElement != nil
    }
}

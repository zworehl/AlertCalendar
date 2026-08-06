import AppKit
import SwiftUI

enum SettingsVisualMetrics {
    static let pageSpacing: CGFloat = 14
    static let sectionContentSpacing: CGFloat = 12
    static let panelPadding: CGFloat = 14
    static let panelCornerRadius: CGFloat = 8
    static let headerIconSize: CGFloat = 15
    static let headerIconFrameSize: CGFloat = 20
    static let headerSpacing: CGFloat = 10
    static let headerTextSpacing: CGFloat = 3
    static let inlineFieldLabelWidth: CGFloat = 96
    static let inlineFieldSpacing: CGFloat = 10
    static let stackedFieldSpacing: CGFloat = 4
    static let checkboxGroupItemSpacing: CGFloat = 18
    static let checkboxGroupGridSpacing: CGFloat = 10
    static let checkboxGroupMinimumItemWidth: CGFloat = 150
    static let checkboxGroupMaximumItemWidth: CGFloat = 220
    static let inlineDividerHeight: CGFloat = 36
    static let cardActionButtonSize: CGFloat = 18
    static let cardActionIconSize: CGFloat = 9
    static let cardActionCornerRadius: CGFloat = 6
    static let navigationStackBreakpoint: CGFloat = 1120
}

enum SettingsTypography {
    static let sectionTitle: Font = .headline
    static let sectionSubtitle: Font = .caption
    static let panelTitle: Font = .subheadline.weight(.semibold)
    static let controlTitle: Font = .subheadline.weight(.semibold)
    static let inlineFieldLabel: Font = .subheadline.weight(.medium)
    static let groupLabel: Font = .caption.weight(.semibold)
    static let supportingText: Font = .caption
    static let metadata: Font = .caption2
    static let metadataEmphasized: Font = .caption2.weight(.semibold)
    static let itemTitle: Font = .subheadline.weight(.semibold)
    static let itemDetail: Font = .caption.weight(.medium)
    static let itemDetailEmphasized: Font = .caption.weight(.semibold)
    static let prominentValue: Font = .system(size: 16, weight: .semibold)
}

struct SettingsSectionHeaderView: View {
    let title: String
    let subtitle: String?
    let detail: String?
    let systemImage: String?
    let iconColor: Color

    init(
        title: String,
        subtitle: String? = nil,
        detail: String? = nil,
        systemImage: String? = nil,
        iconColor: Color = .secondary
    ) {
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.systemImage = systemImage
        self.iconColor = iconColor
    }

    var body: some View {
        HStack(alignment: .top, spacing: SettingsVisualMetrics.headerSpacing) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: SettingsVisualMetrics.headerIconSize, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(
                        width: SettingsVisualMetrics.headerIconFrameSize,
                        height: SettingsVisualMetrics.headerIconFrameSize
                    )
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: SettingsVisualMetrics.headerTextSpacing) {
                Text(title)
                    .font(SettingsTypography.sectionTitle)
                    .foregroundStyle(.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(SettingsTypography.sectionSubtitle)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let detail {
                    Text(detail)
                        .font(SettingsTypography.sectionSubtitle)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsPanelChrome: View {
    var fill: Color = Color(nsColor: .controlBackgroundColor)

    var body: some View {
        RoundedRectangle(cornerRadius: SettingsVisualMetrics.panelCornerRadius, style: .continuous)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: SettingsVisualMetrics.panelCornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }
}

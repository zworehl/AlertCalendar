import AppKit
import SwiftUI

enum SettingsVisualMetrics {
    static let sidebarMinimumWidth: CGFloat = 210
    static let sidebarIdealWidth: CGFloat = 240
    static let sidebarMaximumWidth: CGFloat = 276
    static let sidebarRowHeight: CGFloat = 28
    static let sidebarIconSize: CGFloat = 14
    static let sidebarIconCornerRadius: CGFloat = 5
    static let generalTwoColumnMinimumWidth: CGFloat = 960
    static let detailHorizontalPadding: CGFloat = 24
    static let detailVerticalPadding: CGFloat = 20
    static let pageSpacing: CGFloat = 14
    static let sectionContentSpacing: CGFloat = 12
    static let panelPadding: CGFloat = 14
    static let panelCornerRadius: CGFloat = 10
    static let insetCornerRadius: CGFloat = 8
    static let interactiveCardCornerRadius: CGFloat = 10
    static let interactiveCardPadding: CGFloat = 12
    static let selectionRowCornerRadius: CGFloat = 8
    static let minimumInteractiveControlSize: CGFloat = 28
    static let pageHeaderIconSize: CGFloat = 32
    static let headerIconSize: CGFloat = 15
    static let headerIconFrameSize: CGFloat = 20
    static let headerSpacing: CGFloat = 10
    static let headerTextSpacing: CGFloat = 3
    static let inlineFieldLabelWidth: CGFloat = 96
    static let calendarAlertLabelWidth: CGFloat = 116
    static let inlineFieldSpacing: CGFloat = 10
    static let stackedFieldSpacing: CGFloat = 4
    static let checkboxGroupItemSpacing: CGFloat = 18
    static let checkboxGroupGridSpacing: CGFloat = 10
    static let checkboxGroupMinimumItemWidth: CGFloat = 150
    static let checkboxGroupMaximumItemWidth: CGFloat = 220
    static let inlineDividerHeight: CGFloat = 36
    static let cardActionButtonSize: CGFloat = minimumInteractiveControlSize
    static let cardActionIconSize: CGFloat = 11
    static let cardActionCornerRadius: CGFloat = 6
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
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct SettingsPanelChrome: View {
    var fill: Color = Color(nsColor: .controlBackgroundColor)
    var borderColor: Color?
    var cornerRadius: CGFloat = SettingsVisualMetrics.panelCornerRadius

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fill)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        borderColor ?? Color(nsColor: .separatorColor)
                            .opacity(0.55),
                        lineWidth: 0.5
                    )
            }
    }
}

struct SettingsInsetChrome: View {
    var cornerRadius: CGFloat = SettingsVisualMetrics.insetCornerRadius

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(nsColor: .underPageBackgroundColor).opacity(0.72))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        Color(nsColor: .separatorColor).opacity(0.5),
                        lineWidth: 0.5
                    )
            }
    }
}

struct SettingsInteractiveCardChrome: View {
    let isHovered: Bool
    var isSelected = false
    var tint: Color = .accentColor
    var borderColor: Color?
    var cornerRadius: CGFloat = SettingsVisualMetrics.interactiveCardCornerRadius

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(backgroundColor)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(resolvedBorderColor, lineWidth: 1)
            }
    }

    private var backgroundColor: Color {
        if isSelected {
            return tint.opacity(0.16)
        }
        if isHovered {
            return Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
        }
        return Color(nsColor: .controlBackgroundColor).opacity(0.54)
    }

    private var resolvedBorderColor: Color {
        if let borderColor {
            return borderColor
        }
        if isSelected || isHovered {
            return isSelected ? tint.opacity(0.42) : Color(nsColor: .separatorColor).opacity(0.55)
        }
        return Color(nsColor: .separatorColor).opacity(0.45)
    }
}

struct SettingsSelectionRowChrome: View {
    let isSelected: Bool
    var cornerRadius: CGFloat = SettingsVisualMetrics.selectionRowCornerRadius

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                isSelected
                    ? Color(nsColor: .selectedContentBackgroundColor)
                    : Color.clear
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        isSelected
                            ? Color(nsColor: .selectedContentBackgroundColor)
                            : Color(nsColor: .separatorColor).opacity(0.3),
                        lineWidth: 0.5
                    )
            }
    }
}

struct SettingsControlChrome: View {
    var cornerRadius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        Color(nsColor: .separatorColor).opacity(0.55),
                        lineWidth: 0.5
                    )
            }
    }
}

struct SettingsHoverRowChrome: View {
    let isHovered: Bool
    var cornerRadius: CGFloat = SettingsVisualMetrics.selectionRowCornerRadius

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                isHovered
                    ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
                    : Color.clear
            )
    }
}

struct SettingsStatusBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background {
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.11))
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(tint.opacity(0.18), lineWidth: 0.5)
            }
    }
}

private struct SettingsPanelSurfaceModifier: ViewModifier {
    let padding: CGFloat
    let fill: Color
    let borderColor: Color?
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                SettingsPanelChrome(
                    fill: fill,
                    borderColor: borderColor,
                    cornerRadius: cornerRadius
                )
            )
    }
}

private struct SettingsInsetSurfaceModifier: ViewModifier {
    let padding: CGFloat
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(SettingsInsetChrome(cornerRadius: cornerRadius))
    }
}

extension View {
    func settingsPanelSurface(
        padding: CGFloat = SettingsVisualMetrics.panelPadding,
        fill: Color = Color(nsColor: .controlBackgroundColor),
        borderColor: Color? = nil,
        cornerRadius: CGFloat = SettingsVisualMetrics.panelCornerRadius
    ) -> some View {
        modifier(
            SettingsPanelSurfaceModifier(
                padding: padding,
                fill: fill,
                borderColor: borderColor,
                cornerRadius: cornerRadius
            )
        )
    }

    func settingsInsetSurface(
        padding: CGFloat = SettingsVisualMetrics.interactiveCardPadding,
        cornerRadius: CGFloat = SettingsVisualMetrics.insetCornerRadius
    ) -> some View {
        modifier(SettingsInsetSurfaceModifier(padding: padding, cornerRadius: cornerRadius))
    }
}

struct SettingsSymbolTile: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = SettingsVisualMetrics.sidebarIconSize

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.66, weight: .regular))
            .foregroundStyle(.secondary)
            .symbolRenderingMode(.hierarchical)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct SettingsSidebarIcon: View {
    let systemImage: String
    let isSelected: Bool
    var size: CGFloat = SettingsVisualMetrics.sidebarIconSize

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size, weight: .regular))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(
                isSelected
                    ? Color(nsColor: .selectedControlTextColor)
                    : Color.secondary
            )
            .frame(width: 20, height: 20, alignment: .center)
            .accessibilityHidden(true)
    }
}

struct SettingsPageHeaderView: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SettingsSymbolTile(
                systemImage: systemImage,
                tint: tint,
                size: SettingsVisualMetrics.pageHeaderIconSize
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

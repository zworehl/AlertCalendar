import SwiftUI

enum SettingsLabeledControlLayout: Equatable {
    case inline(labelWidth: CGFloat)
    case stacked

    static var standardInline: Self {
        .inline(labelWidth: SettingsVisualMetrics.inlineFieldLabelWidth)
    }
}

enum SettingsLabeledCheckboxGroupLayout: Equatable {
    case inline
    case adaptive
}

struct SettingsControlLabel: View {
    enum Style {
        case inline
        case compact
    }

    let title: String
    let helpText: String?
    var style: Style = .inline

    var body: some View {
        HStack(spacing: style == .inline ? 6 : 4) {
            Text(title)

            if let helpText {
                InfoTipButton(text: helpText)
            }
        }
        .font(style == .inline ? SettingsTypography.inlineFieldLabel : .caption2.weight(.semibold))
        .foregroundStyle(style == .inline ? Color.primary : Color.secondary)
    }
}

struct SettingsLabeledCheckboxGroup<Content: View>: View {
    let title: String
    let helpText: String?
    let layout: SettingsLabeledCheckboxGroupLayout
    let minimumItemWidth: CGFloat
    let maximumItemWidth: CGFloat
    private let content: Content

    init(
        title: String,
        helpText: String? = nil,
        layout: SettingsLabeledCheckboxGroupLayout = .adaptive,
        minimumItemWidth: CGFloat = SettingsVisualMetrics.checkboxGroupMinimumItemWidth,
        maximumItemWidth: CGFloat = SettingsVisualMetrics.checkboxGroupMaximumItemWidth,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.helpText = helpText
        self.layout = layout
        self.minimumItemWidth = minimumItemWidth
        self.maximumItemWidth = maximumItemWidth
        self.content = content()
    }

    var body: some View {
        Group {
            switch layout {
            case .inline:
                inlineContent
            case .adaptive:
                ViewThatFits(in: .horizontal) {
                    inlineContent
                        .fixedSize(horizontal: true, vertical: false)

                    stackedContent
                }
            }
        }
        .toggleStyle(.checkbox)
        .controlSize(.regular)
        .font(.subheadline)
        .frame(maxWidth: layout == .adaptive ? .infinity : nil, alignment: .leading)
    }

    private var inlineContent: some View {
        HStack(alignment: .center, spacing: SettingsVisualMetrics.inlineFieldSpacing) {
            groupLabel
                .frame(width: SettingsVisualMetrics.inlineFieldLabelWidth, alignment: .leading)

            HStack(alignment: .center, spacing: SettingsVisualMetrics.checkboxGroupItemSpacing) {
                content
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var stackedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            groupLabel

            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: minimumItemWidth, maximum: maximumItemWidth),
                        alignment: .leading
                    ),
                ],
                alignment: .leading,
                spacing: SettingsVisualMetrics.checkboxGroupGridSpacing
            ) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var groupLabel: some View {
        SettingsControlLabel(title: title, helpText: helpText)
    }
}

struct SettingsVerticalDivider: View {
    var height: CGFloat?

    init(height: CGFloat? = nil) {
        self.height = height
    }

    var body: some View {
        Divider()
            .overlay(Color.primary.opacity(0.04))
            .frame(height: height)
            .padding(.vertical, height == nil ? 2 : 0)
            .accessibilityHidden(true)
    }
}

struct SettingsLabeledControl<Content: View>: View {
    let title: String
    let helpText: String?
    let layout: SettingsLabeledControlLayout
    let controlWidth: CGFloat?
    let controlAlignment: Alignment
    private let content: Content

    init(
        title: String,
        helpText: String? = nil,
        layout: SettingsLabeledControlLayout = .standardInline,
        controlWidth: CGFloat? = nil,
        controlAlignment: Alignment = .leading,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.helpText = helpText
        self.layout = layout
        self.controlWidth = controlWidth
        self.controlAlignment = controlAlignment
        self.content = content()
    }

    var body: some View {
        Group {
            switch layout {
            case let .inline(labelWidth):
                HStack(alignment: .center, spacing: SettingsVisualMetrics.inlineFieldSpacing) {
                    SettingsControlLabel(title: title, helpText: helpText)
                        .frame(width: labelWidth, alignment: .leading)

                    positionedContent
                }
            case .stacked:
                VStack(alignment: .leading, spacing: SettingsVisualMetrics.stackedFieldSpacing) {
                    SettingsControlLabel(title: title, helpText: helpText, style: .compact)

                    positionedContent
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var positionedContent: some View {
        if let controlWidth {
            content
                .frame(width: controlWidth, alignment: controlAlignment)
                .frame(maxWidth: .infinity, alignment: controlAlignment)
        } else {
            content
                .frame(maxWidth: .infinity, alignment: controlAlignment)
        }
    }
}

struct SettingsLabeledMenuPicker<SelectionValue: Hashable, Options: View>: View {
    let title: String
    let pickerTitle: String
    let helpText: String?
    let layout: SettingsLabeledControlLayout
    let controlWidth: CGFloat?
    let controlAlignment: Alignment
    @Binding private var selection: SelectionValue
    private let options: Options

    init(
        title: String,
        pickerTitle: String,
        selection: Binding<SelectionValue>,
        helpText: String? = nil,
        layout: SettingsLabeledControlLayout = .standardInline,
        controlWidth: CGFloat? = nil,
        controlAlignment: Alignment = .leading,
        @ViewBuilder options: () -> Options
    ) {
        self.title = title
        self.pickerTitle = pickerTitle
        self.helpText = helpText
        self.layout = layout
        self.controlWidth = controlWidth
        self.controlAlignment = controlAlignment
        _selection = selection
        self.options = options()
    }

    var body: some View {
        SettingsLabeledControl(
            title: title,
            helpText: helpText,
            layout: layout,
            controlWidth: controlWidth,
            controlAlignment: controlAlignment
        ) {
            Picker(pickerTitle, selection: $selection) {
                options
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }
}

struct SettingsAddToCalendarPicker: View {
    @Binding private var selection: String
    let calendars: [AvailableCalendar]
    let pickerTitle: String
    let helpText: String
    let emptySelectionTitle: String?

    init(
        selection: Binding<String>,
        calendars: [AvailableCalendar],
        pickerTitle: String,
        helpText: String,
        emptySelectionTitle: String? = nil
    ) {
        _selection = selection
        self.calendars = calendars
        self.pickerTitle = pickerTitle
        self.helpText = helpText
        self.emptySelectionTitle = emptySelectionTitle
    }

    var body: some View {
        SettingsLabeledMenuPicker(
            title: "Add To",
            pickerTitle: pickerTitle,
            selection: $selection,
            helpText: helpText
        ) {
            if let emptySelectionTitle {
                Text(emptySelectionTitle).tag("")
            }

            ForEach(calendars) { calendar in
                Text(calendar.title).tag(calendar.id)
            }
        }
    }
}

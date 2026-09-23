import AppKit
import Combine
import Contacts
import CoreLocation
import EventKit
import SwiftUI

extension SettingsView {
    func generalSettingStepperControl<Control: View>(
        valueText: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            control()
            Text(valueText)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(minWidth: 164, alignment: .trailing)
    }

    func generalSettingPickerControl<Control: View>(
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack {
            Spacer(minLength: 0)
            control()
        }
        .frame(minWidth: 164, alignment: .trailing)
    }

    func showcaseTimeChip(_ title: String, isHighlighted: Bool) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isHighlighted ? Color.red : .primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isHighlighted ? Color.red.opacity(0.14) : Color.primary.opacity(0.08))
            )
    }

    func showcaseQueueChip(_ title: String, isHighlighted: Bool = false) -> some View {
        Text(title)
            .font(.caption2.weight(.medium))
            .foregroundStyle(isHighlighted ? .primary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isHighlighted ? Color.primary.opacity(0.12) : Color.primary.opacity(0.06))
            )
    }

    func showcaseTag(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color(red: 0.24, green: 0.59, blue: 0.97))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color(red: 0.24, green: 0.59, blue: 0.97).opacity(0.14))
            )
    }

    var showcaseMenuBarTitle: String {
        let fullTitle = "Quarterly planning with product and operations"
        guard draft.useEventTitleEllipsis else { return fullTitle }
        if draft.rewriteEventTitlesWithAppleIntelligence && appleIntelligenceTitleRewriteIsAllowed {
            let rewrittenTitle = "Quarterly product planning"
            if rewrittenTitle.count <= draft.eventTitleMaxCharacters {
                return rewrittenTitle
            }
        }
        return showcaseTrimmedTitle(fullTitle, maxLength: draft.eventTitleMaxCharacters)
    }

    var appleIntelligenceTitleRewriteIsAllowed: Bool {
        AppSettingsRules.allowsAppleIntelligenceTitleRewrite(
            maximumCharacters: draft.eventTitleMaxCharacters
        )
    }

    var eventTitleMaxCharactersBinding: Binding<Int> {
        Binding {
            draft.eventTitleMaxCharacters
        } set: { newValue in
            let normalizedValue = AppSettingsRules.normalizedEventTitleMaxCharacters(newValue)
            draft.eventTitleMaxCharacters = normalizedValue
            if !AppSettingsRules.allowsAppleIntelligenceTitleRewrite(maximumCharacters: normalizedValue) {
                draft.rewriteEventTitlesWithAppleIntelligence = false
                draft.useMailContextForEventTitleRewrite = false
            }
        }
    }

    var eventTitleRewriteBinding: Binding<Bool> {
        Binding {
            draft.rewriteEventTitlesWithAppleIntelligence && appleIntelligenceTitleRewriteIsAllowed
        } set: { newValue in
            let isAllowed = AppSettingsRules.allowsAppleIntelligenceTitleRewrite(
                maximumCharacters: draft.eventTitleMaxCharacters
            )
            draft.rewriteEventTitlesWithAppleIntelligence = newValue && isAllowed
            if !draft.rewriteEventTitlesWithAppleIntelligence {
                draft.useMailContextForEventTitleRewrite = false
            }
        }
    }

    var useRewrittenEventTitlesInDropdownBinding: Binding<Bool> {
        Binding {
            draft.useRewrittenEventTitlesInDropdown && draft.useEventTitleEllipsis
        } set: { newValue in
            draft.useRewrittenEventTitlesInDropdown = newValue
        }
    }

    var eventTitleRewriteAvailabilityMessage: String? {
        guard appleIntelligenceTitleRewriteIsAllowed else {
            return "Apple Intelligence title rewriting becomes available at 10 characters or more."
        }
        guard !agendaSummaryAvailability.isAvailable else { return nil }
        switch agendaSummaryAvailability {
        case .available:
            return nil
        case .unsupportedSystem:
            return "Title rewriting requires macOS 26 or later."
        case .deviceNotEligible:
            return "Apple Intelligence title rewriting isn't supported on this Mac."
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in System Settings to rewrite titles."
        case .modelNotReady:
            return "Apple Intelligence is still preparing its on-device model."
        }
    }

    var showcaseDropdownItems: [String] {
        let samples = [
            "Standup in 15m",
            "Design review in 2h",
            "Lunch in 3h",
            "Retro in 5h",
            "Town hall tomorrow"
        ]
        return Array(samples.prefix(min(max(draft.maxListItems, 1), samples.count)))
    }

    func showcaseTrimmedTitle(_ title: String, maxLength: Int) -> String {
        let normalizedLength = max(1, maxLength)
        guard title.count > normalizedLength else { return title }
        return String(title.prefix(max(1, normalizedLength - 1))) + "..."
    }
}

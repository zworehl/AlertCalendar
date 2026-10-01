import SwiftUI

extension SettingsView {
    var languageSettingsSection: some View {
        settingsSection(
            title: L10n.text("Language"),
            subtitle: L10n.text("Choose the language used by AlertCalendar."),
            systemImage: "globe"
        ) {
            SettingsLabeledMenuPicker(
                title: L10n.text("App language"),
                pickerTitle: L10n.text("App language"),
                selection: $draft.language,
                helpText: L10n.text("The language changes when you apply your settings.")
            ) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.nativeName).tag(language)
                }
            }
        }
    }
}

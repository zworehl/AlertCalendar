import AppKit
import Combine
import Contacts
import CoreLocation
import EventKit
import SwiftUI

extension SettingsView {
    @ViewBuilder
    var activeSettingsContent: some View {
        switch selectedTab {
        case .general:
            generalSettingsContent
        case .feeds:
            liveFeedsSettingsContent
        case .calendars:
            calendarSettingsContent
        case .permissions:
            permissionsSettingsContent
        }
    }
}

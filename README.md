# AlertCalendar

Menu bar app in Swift that shows upcoming Calendar events and Reminders, including source calendar colors, Focus mode status, and a red blinking alert when an item is 5 minutes away (configurable).

## Run

1. Open this folder in Xcode.
2. Select the `AlertCalendar` scheme.
3. Run the app (`Cmd + R`).

## Permissions

On first launch, allow:

- Calendar access
- Reminders access
- Focus status access (if prompted by macOS)

## Features

- Menu bar text with upcoming items and countdown.
- Event/Reminder list with calendar colors.
- Focus mode status line (`On` / `Off` / permission state).
- Red blinking alert in the menu bar and dropdown when an item is inside the alert window.
- Settings window in English with:
  - event/reminder toggles
  - look-ahead window
  - alert lead time (default 5 minutes)
  - number of items shown

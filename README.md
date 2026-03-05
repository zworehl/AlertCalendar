# AlertCalendar

AlertCalendar is a macOS menu bar app that shows upcoming Calendar events and Reminders with visual alerts.

## Requirements
- macOS 13+
- Xcode Command Line Tools (`xcode-select --install`)
- Swift 6.2+

## Install
Use the local installer:
```bash
./install.sh
```

Detailed options: [INSTALL.md](INSTALL.md)

## Run in Development
```bash
swift run
```

## Run Tests
```bash
swift test
```

## Coverage Gate (97%)
```bash
./scripts/check_coverage.sh
```

## Permissions
On first launch, allow:
- Calendar access
- Reminders access
- Focus status access (if prompted)

## Main Features
- Menu bar text with upcoming items and countdown.
- Event/Reminder list with calendar colors.
- Focus mode status line.
- Red blinking alert when an item is inside the alert window.
- Settings for look-ahead window, alert lead time, and list size.

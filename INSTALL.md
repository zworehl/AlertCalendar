# Installation (macOS)

## Quick Install
```bash
./install.sh
```

By default it installs the app in `/Applications/AlertCalendar.app`.

## Optional Flags
- Install to custom directory:
```bash
APP_DIR="$HOME/Applications" ./install.sh
```
- Install without auto-open:
```bash
OPEN_AFTER_INSTALL=0 ./install.sh
```

## Development Run
```bash
swift run
```

## Tests
```bash
swift test
```

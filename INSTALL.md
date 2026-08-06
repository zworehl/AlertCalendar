# Installation (macOS)

## Quick Install
```bash
./install.sh
```

By default it installs the app in `/Applications/AlertCalendar.app`.

The installer removes duplicate `AlertCalendar.app` copies from `/Applications` and `~/Applications`, then signs the new bundle with an Apple Development identity so macOS permissions keep a stable application identity.

## Optional Flags
- Install to custom directory:
```bash
APP_DIR="$HOME/Applications" ./install.sh
```
- Install without auto-open:
```bash
OPEN_AFTER_INSTALL=0 ./install.sh
```
- Use a specific Apple Development identity:
```bash
CODE_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./install.sh
```

## Development Run
```bash
swift run
```

## Tests
```bash
swift test
```

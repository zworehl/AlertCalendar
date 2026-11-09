# Installation (macOS)

## Quick Install
```bash
./install.sh
```

By default it installs the app in `/Applications/AlertCalendar.app`.

The installer prepares the new bundle in a private staging directory on the destination filesystem. It copies resources, signs with an Apple Development identity, verifies the signature, and runs the app's isolated offline smoke session before stopping or replacing the installed app. The stable signing identity preserves macOS permission associations.

The previous bundle remains available until replacement and launch verification succeed. A failed replacement or launch restores it; if recovery itself fails, the installer prints the preserved backup path instead of deleting it. Duplicate bundles are removed and unregistered only after a successful installation.

AlertCalendar starts as a menu bar app. Only its Settings window makes it appear in the Dock; automation helpers remain invisible. Opening it again brings the existing instance's Settings window forward.

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
./scripts/verify.sh
```

The same entry point is used by pull-request CI and release CI. It checks architecture, bilingual strings, installer/release helpers, the Swift suite once with coverage, then a signed disposable app bundle. The bundle's `--smoke-test --report <path>` session exercises menu/settings presentation with temporary state, offline and denied-access cases; it does not access accounts, prompt for permissions, or stop the installed app.

`.build/coverage-report.json` reports coverage across all instrumented application sources separately from the selected foundation gate and gradual subsystem risk gates. Re-report existing results with `./scripts/check_coverage.sh --skip-tests`. `VERIFY_BUNDLE=0` omits only the disposable bundle stage when a caller separately performs the real installation and bundle validation.

CI exercises macOS 15 and macOS 26. The declared macOS 13 deployment target remains checked at compilation; running on macOS 13 still requires a separate compatibility machine because GitHub does not provide a hosted macOS 13 runner.

# Releases and automatic updates

AlertCalendar uses Sparkle 2, GitHub Releases, and GitHub Pages for signed automatic updates. The public source repository and releases live at `https://github.com/zworehl/AlertCalendar`, while the app reads its update feed from `https://zworehl.github.io/AlertCalendar/appcast.xml`.

## One-time GitHub setup

Add `SPARKLE_PRIVATE_KEY` to the Actions secrets in `zworehl/AlertCalendar`. It is the exact contents exported by Sparkle's `generate_keys -x` command for account `AlertCalendar` and is required for every release.

Add the following secrets when a Developer ID Application certificate and Apple notarization credentials become available:

- `DEVELOPER_ID_APPLICATION_P12_BASE64`: the exported Developer ID Application certificate and private key, base64 encoded.
- `DEVELOPER_ID_APPLICATION_PASSWORD`: the password used when exporting that `.p12` file.
- `APPLE_API_PRIVATE_KEY_BASE64`: the App Store Connect API `.p8` key, base64 encoded.
- `APPLE_API_KEY_ID`: the API key ID.
- `APPLE_API_ISSUER_ID`: the API issuer ID.

The Sparkle public key is committed only in `install.sh`. Its private counterpart remains in the local login Keychain and must only be copied into the encrypted GitHub secret.

In repository Settings > Pages, select **GitHub Actions** as the publishing source before creating the first tag.

When all Developer ID and notarization secrets are present, the workflow signs and notarizes the app. If none are configured, it produces an ad hoc signed Apple-silicon public preview with explicit first-launch instructions. A partial Apple signing configuration fails instead of silently falling back.

## Publishing

1. Update `VERSION` and increment `BUILD_NUMBER` for every build.
2. Run `./scripts/verify.sh` and `./install.sh` locally.
3. Commit and push the release changes.
4. Create and push the matching tag, for example `git tag -a v1.0.0 -m "AlertCalendar 1.0.0" && git push origin v1.0.0`.

The release workflow rejects a tag that does not match `VERSION`. It runs the test and architecture gates, creates a Sparkle-signed archive, checksum, appcast, GitHub Release, and Pages deployment. When Apple distribution credentials are configured, it additionally imports the Developer ID certificate, notarizes the app, and staples the ticket.

An Apple Development certificate is suitable for local installation but not for public notarization. Replace an ad hoc preview with a new build number after Developer ID credentials become available; never reuse a published archive under the same build number.

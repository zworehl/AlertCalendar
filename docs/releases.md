# Releases and automatic updates

AlertCalendar uses Sparkle 2, GitHub Releases, and GitHub Pages for signed automatic updates. The source repository is private, so the app reads the public feed at `https://zworehl.github.io/AlertCalendar/appcast.xml`; release archives and the appcast are deployed to that Pages site as well as attached to the corresponding GitHub Release.

## One-time GitHub setup

Add these Actions secrets to `zworehl/AlertCalendar`:

- `DEVELOPER_ID_APPLICATION_P12_BASE64`: the exported Developer ID Application certificate and private key, base64 encoded.
- `DEVELOPER_ID_APPLICATION_PASSWORD`: the password used when exporting that `.p12` file.
- `APPLE_API_PRIVATE_KEY_BASE64`: the App Store Connect API `.p8` key, base64 encoded.
- `APPLE_API_KEY_ID`: the API key ID.
- `APPLE_API_ISSUER_ID`: the API issuer ID.
- `SPARKLE_PRIVATE_KEY`: the exact contents exported by Sparkle's `generate_keys -x` command for account `AlertCalendar`.

The Sparkle public key is committed only in `install.sh`. Its private counterpart remains in the local login Keychain and must only be copied into the encrypted GitHub secret.

In repository Settings > Pages, select **GitHub Actions** as the publishing source before creating the first tag. GitHub Pages from a private repository requires GitHub Pro, Team, or Enterprise; the deployed update files are intentionally public even though the source stays private. If that plan is unavailable, use a separate public Pages repository for the update artifacts and change `SPARKLE_FEED_URL` plus the workflow's download URL prefix before releasing.

## Publishing

1. Update `VERSION` and increment `BUILD_NUMBER` for every build.
2. Run `./scripts/verify.sh` and `./install.sh` locally.
3. Commit and push the release changes.
4. Create and push the matching tag, for example `git tag -a v1.0.0 -m "AlertCalendar 1.0.0" && git push origin v1.0.0`.

The release workflow rejects a tag that does not match `VERSION`. It runs the test and architecture gates, imports the Developer ID certificate into a temporary keychain, builds and signs the app, submits it to Apple's notarization service, staples the ticket, creates a Sparkle-signed archive and appcast, and publishes both files in a non-draft GitHub Release.

Never create the release tag before the required secrets and a Developer ID Application certificate are available. An Apple Development certificate is suitable for local installation but not for public distribution or notarization.

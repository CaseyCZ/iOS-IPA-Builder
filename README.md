# iOS IPA Builder

Build clean iOS IPA packages with GitHub Actions — without needing a local Mac.

> Status: early development. Clean unsigned IPA builds are enabled for native Xcode, Capacitor, Flutter and React Native projects.

## Build modes

### Unsigned IPA
Creates a clean unsigned IPA from the application's own source code.

Intended for tools and workflows that perform their own signing, such as AltStore, SideStore and compatible IPA/container workflows.

### App Store / TestFlight
Uses the user's own Apple distribution signing credentials.

The current stage validates the signing configuration and installs it into a temporary macOS keychain for verification. The matching provisioning profile is installed only for the job and removed again before the runner finishes. Signed archive creation and IPA export will be enabled in the next stage.

Configure these repository secrets in the user's own builder repository or fork:

- `APPLE_CERTIFICATE_P12_BASE64` — Apple Distribution certificate exported as a Base64-encoded `.p12`.
- `APPLE_CERTIFICATE_PASSWORD` — password for that `.p12`.
- `APPLE_PROVISIONING_PROFILE_BASE64` — matching App Store Connect provisioning profile encoded as Base64.
- `APPLE_TEAM_ID` — 10-character Apple Developer Team ID.

Signing material is never committed to the repository and is only exposed to the workflow through GitHub encrypted secrets.

## Supported project types

Source inspection currently recognizes and can build unsigned IPA packages for:

- Native Xcode
- Capacitor
- Flutter
- React Native

`Auto` is the recommended default. It detects common project markers such as `capacitor.config.*`, `pubspec.yaml`, React Native dependencies and Xcode projects/workspaces. A project type can still be selected manually when needed.

## Security model

This repository is public and contains only build infrastructure.

- No application source code is stored here by default.
- No Apple credentials are bundled with the project.
- No developer secrets are committed to the repository.
- Public source repositories can be inspected without a source token.
- Private applications require the owner to provide their own fine-grained read-only source token as the `SOURCE_TOKEN` repository secret.
- The source token is used only while fetching the selected source and is not persisted in its Git configuration.
- Public users should fork this repository and configure their own secrets in their fork.
- Source inspection does not execute code from the selected application.
- Unsigned IPA output can be delivered to either a private or public repository.
- Private is the default. The builder verifies that the destination repository visibility matches the selected output mode before uploading the IPA.
- No IPA is stored as a GitHub Actions artifact or cache.
- Build jobs are restricted to standard GitHub-hosted runners; larger/xlarge/custom/self-hosted runner labels are intentionally blocked.

## IPA delivery

Choose `Private` or `Public` in the workflow. Private is the default.

Configure these repository secrets in your builder repository or fork:

- `OUTPUT_REPO` — target repository in `owner/repo` format.
- `OUTPUT_TOKEN` — fine-grained token with permission to create releases and upload assets in that target repository.

For private application source repositories also configure:

- `SOURCE_TOKEN` — fine-grained read-only token for the source repository.

The output repository must already exist. Each successful build creates a unique prerelease with the IPA attached. If the selected visibility does not match the actual repository visibility, delivery is blocked.

## Current stage

Available now:

- workflow UI
- safe public/private source fetch
- project auto-detection
- standard macOS runner only
- one workflow run at a time
- clean unsigned Release build for native Xcode, Capacitor, Flutter and React Native
- standard `Payload/App.app` IPA packaging
- SHA-256 and size reporting
- private GitHub Release delivery
- no GitHub Actions artifact/cache storage

Next stages:

- App Store / TestFlight archive signing and IPA export

## License

License will be added before the first public release.

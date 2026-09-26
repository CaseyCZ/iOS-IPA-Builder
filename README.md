# iOS IPA Builder

Build clean iOS IPA packages with GitHub Actions — without needing a local Mac.

> Status: early development. Clean unsigned IPA builds are enabled for native Xcode and Capacitor projects.

## Build modes

### Unsigned IPA
Creates a clean unsigned IPA from the application's own source code.

Intended for tools and workflows that perform their own signing, such as AltStore, SideStore and compatible IPA/container workflows.

### App Store / TestFlight
Creates a normal release build using the user's own Apple signing credentials.

Apple certificates, provisioning profiles and App Store Connect credentials will always belong to the user and must be configured in their own GitHub repository/fork as encrypted secrets.

## Supported project types

Source inspection currently recognizes:

- Native Xcode — unsigned build enabled
- Capacitor — unsigned build enabled
- Flutter — detection enabled, build support next
- React Native — detection enabled, build support next

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
- Build outputs will not be published automatically from this repository.
- Build jobs are restricted to standard GitHub-hosted runners; larger/xlarge/custom/self-hosted runner labels are intentionally blocked.

## Current stage

Available now:

- workflow UI
- safe public/private source fetch
- project auto-detection
- standard macOS runner only
- one workflow run at a time
- clean unsigned Release build for native Xcode and Capacitor
- standard `Payload/App.app` IPA packaging
- SHA-256 and size reporting
- no GitHub Actions artifact/cache storage

Next stages:

- Flutter unsigned builds
- React Native unsigned builds
- private output delivery
- App Store / TestFlight signing with the user's own Apple credentials

## License

License will be added before the first public release.

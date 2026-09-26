# iOS IPA Builder

Build clean iOS IPA packages with GitHub Actions — without needing a local Mac.

> Status: early development. The build engine is not enabled yet.

## Build modes

### Unsigned IPA
Creates a clean unsigned IPA from the application's own source code.

Intended for tools and workflows that perform their own signing, such as AltStore, SideStore and compatible IPA/container workflows.

### App Store / TestFlight
Creates a normal release build using the user's own Apple signing credentials.

Apple certificates, provisioning profiles and App Store Connect credentials will always belong to the user and must be configured in their own GitHub repository/fork as encrypted secrets.

## Supported project types

Planned:

- Native Xcode
- Capacitor
- Flutter
- React Native

The builder will also include an `Auto detect` mode where possible.

## Security model

This repository is public and contains only build infrastructure.

- No application source code is stored here by default.
- No Apple credentials are bundled with the project.
- No developer secrets are committed to the repository.
- Private applications will require the owner to provide their own read-only source access token.
- Public users should fork this repository and configure their own secrets in their fork.
- Build outputs will not be published automatically from this repository.

## Current stage

The workflow UI is being built first. Build execution, project detection, signing and private output handling will be added in separate steps.

## License

License will be added before the first public release.

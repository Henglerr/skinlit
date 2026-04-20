fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios readiness_doctor

```sh
[bundle exec] fastlane ios readiness_doctor
```

Run the repo's submission readiness doctor

### ios asc_doctor

```sh
[bundle exec] fastlane ios asc_doctor
```

Run the App Store Connect subscription doctor

### ios site_validate

```sh
[bundle exec] fastlane ios site_validate
```

Validate the legal site package and public launch URLs

### ios precheck_metadata

```sh
[bundle exec] fastlane ios precheck_metadata
```

Run fastlane precheck against the current App Store metadata

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Archive the Release build and upload it to TestFlight

### ios metadata

```sh
[bundle exec] fastlane ios metadata
```

Upload local App Store metadata without touching the binary

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Upload screenshots already present in fastlane/screenshots

### ios submit_review

```sh
[bundle exec] fastlane ios submit_review
```

Submit the prepared metadata, screenshots, and selected build for App Review

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).

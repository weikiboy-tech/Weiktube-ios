# Build and test Weiktube for iOS

The repository contains an actual Xcode project, a shared `Weiktube` scheme, four targets, and a macOS CI workflow. The deployment target is **iOS 17.0**, with iPhone and iPad supported. The iOS app's initial version is **0.1.0, build 1**; Android 1.3.23 is the feature reference, not an iOS build result.

## Targets and source membership

| Target | Product | Sources |
| --- | --- | --- |
| `Weiktube` | `Weiktube.app` | Swift sources under `Weiktube`, excluding `AdBlock/VendorSource` |
| `ShareExtension` | `ShareExtension.appex` | Share controller plus the Foundation-only link router, atomic JSON storage and shared-link inbox |
| `WeiktubeTests` | XCTest bundle | Swift tests under `WeiktubeTests` |
| `WeiktubeUITests` | UI test bundle | Offline launch, native tab navigation, search sheet and unsafe-link rejection |

The app embeds the extension. The bundle contains `MediaBridge.js`, the complete `Filters` folder, the asset catalog, privacy manifest, `LICENSE`, and `THIRD-PARTY-NOTICES.md`. Upstream vendor source archives are retained in the repository for licensing/provenance and are **not app resources**.

Signed filter payloads and pinned vendor inputs must retain their exact original bytes, including line endings. `.gitattributes` disables Git text conversion for those files. Do not reformat them: signature/provenance verification deliberately detects byte changes.

`scripts/generate-project.py` uses Python's standard library and stable object identifiers. After adding, deleting or moving a source or resource file, regenerate and validate:

```sh
python3 scripts/generate-project.py
python3 scripts/validate-project.py
```

CI runs the generator with `--check`; it fails when the checked-in project omits newly added files. The structural validator parses the project graph and checks target membership, resource inclusion, extension embedding, both test targets, app-group settings, and the OAuth plist preparation. It does not compile Swift or prove runtime behavior.

## Local simulator build

Use a Mac with Xcode that includes an iOS 17 or later SDK and an installed iPhone simulator runtime. Open `Weiktube.xcodeproj`, select the shared `Weiktube` scheme, then select an available iPhone or iPad simulator. Simulator builds disable signing and require no Apple team or Google OAuth client.

The command below prints an available iPhone simulator destination without assuming a particular device name:

```sh
python3 scripts/select-simulator.py
```

Use the printed destination in the following command:

```sh
xcodebuild \
  -project Weiktube.xcodeproj \
  -scheme Weiktube \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=THE-PRINTED-SIMULATOR-UUID' \
  -derivedDataPath build/DerivedData \
  -resultBundlePath artifacts/Weiktube-Simulator.xcresult \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO \
  build test
```

Create the `artifacts` parent folder before using a result-bundle path. An `.xcresult` path must not already contain a result bundle from a previous run. The shared scheme runs both XCTest and UI tests. UI tests supply `--ui-testing`, which skips initial remote-page loading; they do not authenticate, post account actions, or reset production preferences. Settings persistence and clear-history callback protection are covered by separate unit tests.

For Xcode analysis, replace `build test` with `analyze` and use a different result-bundle path. Analysis is an additional build check, not a live-site or physical-device acceptance result.

## Portable checks

The Foundation-only Swift package covers URL validation, player presentation transitions, atomic persistence and app/extension queue coordination. It intentionally excludes UIKit, WebKit, Combine stores, OAuth and UI tests:

```sh
swift test
node WeiktubeTests/FilterRuntimeTests.cjs
```

The Node fixture suite exercises the real bundled filter runtime and pinned vendor provenance without contacting YouTube. It cannot prove WebKit behavior on an iPhone. The CI workflow uses Node 22. Swift test outcomes, compiler diagnostics and Xcode results should be read from the actual run; the presence of a test source is not a passing result.

## Configuration and derived Info.plist

`Config/Debug.xcconfig` and `Config/Release.xcconfig` share `Config/Base.xcconfig`. The base file optionally includes ignored `Config/Local.xcconfig`; `Config/Local.example.xcconfig` documents the supported overrides. No development team is invented or checked in.

| Setting | Public default | Purpose |
| --- | --- | --- |
| `WEIKTUBE_BUNDLE_ID` | `com.weiktube.ios` | Main app identifier; extension adds `.share` |
| `WEIKTUBE_APP_GROUP` | `group.com.weiktube.ios` | Shared-link queue; must be provisioned for both targets for device sharing |
| `DEVELOPMENT_TEAM` | empty | Your actual Apple signing team for device builds |
| `GOOGLE_OAUTH_CLIENT_ID` | empty | Real registered iOS Google OAuth client |
| `GOOGLE_REVERSED_CLIENT_ID` | empty | Matching callback URL scheme |
| `GOOGLE_OAUTH_REDIRECT_URI` | empty | Matching scheme followed by `:/oauthredirect` |

With empty Google settings, the app builds with public browsing and displays a configuration explanation when native Google sign-in is requested. It does not pretend to be connected. `scripts/prepare-info.py` produces a declared derived plist during the build. It registers `weiktube` unconditionally and adds the Google callback only when all three settings are present and agree. Partial or mismatched configuration fails the preparation step. The source plist is never rewritten with local credentials or identifiers. Xcode's supported script input/output mechanism is described in [Running custom scripts during a build](https://developer.apple.com/documentation/xcode/running-custom-scripts-during-a-build).

On iPhone, supported orientations are portrait and both landscapes. On iPad, the app declares all four orientations to retain multitasking support; the player reducer still ignores inverted sensor readings. Apple's [supported interface orientations documentation](https://developer.apple.com/documentation/uikit/uiviewcontroller/supportedinterfaceorientations) explains the iPad multitasking requirement.

## CI artifacts and what they mean

`.github/workflows/ios.yml` runs structural/provenance checks, the portable package tests, then build, XCTest, UI tests and analysis on `macos-15`. It discovers an installed iPhone simulator dynamically. It uploads logs and `.xcresult` bundles even on failure, together with a simulator `.app` zip when compilation produced one.

The artifact name includes **`unsignedSimulator`**. That app is for the simulator; it is not an iPhone IPA, and its existence does not mean every test passed. Check the job outcome and result bundle.

Manual workflow dispatch can optionally create an **`unsignedDevice` `.xcarchive`** using a generic iOS destination and `CODE_SIGNING_ALLOWED=NO`. The workflow does not export an IPA, install anything on a device, or publish a release. A signed device distribution still needs your actual team, certificates/profiles, identifiers, App Group entitlement and chosen distribution method. See [INSTALLATION.md](INSTALLATION.md).

## Remaining verification boundary

A Linux Swift/package check cannot build Apple frameworks or run an iOS simulator. Until a real Xcode run succeeds, app compilation and Apple runtime tests remain unverified. Native Google account actions additionally need a configured client and user consent. Website login, third-party service behavior, uninterrupted YouTube playback, PiP and orientation/audio gestures need physical-device acceptance. A structural check or unsigned archive does not satisfy those gates.

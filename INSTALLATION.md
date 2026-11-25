# Install and sign Weiktube for iOS

## Auf iPhone oder iPad installieren

**Private IPA für den Freundeskreis.** Registriere die vorgesehenen iPhones im Apple-Developer-Team. Richte auf dem Mac die Signierung für App und Share Extension ein (siehe unten) und starte `bash scripts/archive-for-testflight.sh --friends`. Xcode exportiert die signierte Datei lokal unter `build/Weiktube-…-private/Weiktube.ipa`. Schicke die IPA direkt an die vorgesehenen Personen. Sie können sie über Apple Configurator auf den registrierten Geräten installieren. [Apple-Anleitung für registrierte Geräte](https://developer.apple.com/documentation/xcode/distributing-apps-to-your-development-devices)

**Private Einladung per E-Mail.** Sobald der Herausgeber einen signierten Build bereitgestellt hat, installiere **TestFlight** aus dem App Store, öffne die Einladung auf dem Gerät und tippe bei **Weiktube** auf **Installieren**. Weitere Builds erscheinen in derselben App. Den ersten Build für externe Tester prüft Apple. [Apple TestFlight](https://developer.apple.com/testflight/)

Der öffentliche GitHub-Quellstand allein erzeugt keine Einladung. Für den ersten Upload benötigt der Herausgeber Zugriff auf sein Apple-Developer-Team, den App-Store-Connect-Eintrag und die zur App und Share Extension gehörenden App-Group-Profile. Die Schritte für das signierte Archiv stehen unten.


The source tree is ready to open in Xcode. It does not contain an Apple team, signing certificate, provisioning profile, Google OAuth client or a pre-signed IPA. The app requires iOS 17 or later. Choose the simulator path for local review without signing, or configure your actual Apple development team for an iPhone/iPad build.

## Simulator review

1. Open `Weiktube.xcodeproj` on a Mac with Xcode and an installed iOS 17+ simulator runtime.
2. Select scheme `Weiktube` and an available simulator.
3. Run the app, or use Product → Test for the unit and offline UI suites.

The native Google sign-in button shows a configuration message until a real iOS OAuth client is supplied. Original YouTube browsing and the separately retained website session are independent of that native authorization. The Share Extension's queue requires a working App Group; the app also provides direct link input and its documented `weiktube://` URL route.

A downloaded CI artifact labelled `unsignedSimulator` contains a simulator `.app`, not a device-installable IPA. Unzip it on a Mac, boot a compatible simulator, and install the app with:

```sh
xcrun simctl install booted /absolute/path/to/Weiktube.app
xcrun simctl launch booted com.weiktube.ios
```

Use the configured bundle identifier if you changed the public default. A CI artifact may exist even when a later test failed; read the attached `.xcresult` and job status before treating it as a verified build.

## Configure device signing

1. Add your Apple account in Xcode Settings → Accounts. Select an actual development team that can provision the capabilities used by the app and extension.
2. Register or select your unique app identifier and its `.share` extension identifier. Register one App Group and enable it for both. Apple's [Configuring App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups) describes this entitlement and shared container.
3. Copy `Config/Local.example.xcconfig` to `Config/Local.xcconfig`. Set `DEVELOPMENT_TEAM`, `WEIKTUBE_BUNDLE_ID` and `WEIKTUBE_APP_GROUP` to the real values. This local file is ignored by git. The project does not supply a team ID.
4. Check Signing & Capabilities for both `Weiktube` and `ShareExtension`. The group and team must agree; the extension identifier derives from the app identifier. Let Xcode create/download the matching development profiles if your account is authorized to do so.
5. Connect the iPhone or iPad, trust the Mac, enable Developer Mode when requested, select the device destination, and run. Apple's [Running your app in Simulator or on a device](https://developer.apple.com/documentation/xcode/running-your-app-in-simulator-or-on-a-device) covers the device workflow.

If the selected team cannot provision the App Group, the complete signed app/extension build remains blocked on that capability. Do not rename an unsigned archive to `.ipa` or assume a simulator build can be installed on a phone. When a running build cannot access its shared group, the app reports that problem and supports normal link entry; it does not force-launch from the Share Extension using a private API.

## Native Google account authorization

Create a Google **iOS** OAuth client for the actual app bundle identifier, enable the YouTube Data API for the intended Google Cloud project, and configure the consent screen/test users as applicable. Put the real client ID, matching reverse-DNS scheme and matching `:/oauthredirect` URI into the three `GOOGLE_*` settings in `Config/Local.xcconfig`. The build validates that they agree before registering the callback URL scheme. See [Google's OAuth documentation for installed apps](https://developers.google.com/identity/protocols/oauth2/native-app).

The application uses the system authentication session and PKCE. It does not use an Android client ID, a client secret, pasted website cookies or an embedded OAuth login form. Native authorization provides the implemented API features; it does not automatically sign the original YouTube website into the same account. Read scope is requested separately from the explicit write-permission flow used for account actions.

## Signed Release archive and distribution

After the simulator tests and device acceptance are satisfactory:

1. Verify the app version/build number, final identifiers, App Group, privacy declarations and bundled license notices.
2. Select the `Weiktube` scheme and a generic iOS device destination in Xcode.
3. Choose Product → Archive with your real signing configuration. The shared scheme archives **Release**. Both the app and its embedded Share Extension must sign successfully.
4. In Organizer, validate and distribute using the route your account and profiles support. A device/ad hoc export requires an appropriate distribution profile and registered devices; TestFlight/App Store distribution requires an App Store Connect app and the corresponding program access. Xcode's [Distributing your app for beta testing and releases](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases) describes those supported workflows.

Alternativ erstellt `bash scripts/archive-for-testflight.sh` auf dem eingerichteten Mac das Release-Archiv, prüft App und eingebettete Share Extension und öffnet das Archiv in Xcode. Im Organizer **Distribute App → App Store Connect** wählen. In App Store Connect unter **TestFlight** den verarbeiteten Build einer Testgruppe zuordnen und eine Einladung erzeugen.

The repository does not commit export credentials, select a real team on your behalf, upload a build or promise App Store approval. No automated release publication is configured.

The optional CI `unsigned_device_archive` input creates an unsigned device `.xcarchive` solely for build inspection. It deliberately does **not** export an IPA. To obtain an installable signed build, perform a real signed archive/export with your team and distribution settings; the unsigned artifact alone cannot satisfy that requirement.

## Personal testing and other supported distribution routes

A free Xcode **Personal Team** can be useful for personal device experiments, but its provisioning expires and its capability availability is limited. This project deliberately uses App Groups for its complete app/extension handoff. Check the capabilities Xcode can actually provision for your team; a Personal Team is not assumed to sign the complete feature set. Apple's [developer account overview](https://developer.apple.com/help/account/basics/about-your-developer-account/) explains periodic reprovisioning, and [supported iOS capabilities](https://developer.apple.com/help/account/reference/supported-capabilities-ios) is the authoritative capability reference.

| Route | Suitable use | Required next step for this project |
| --- | --- | --- |
| Xcode development signing | Developer review on your own registered devices | Real team/profile, working App Group, successful app/extension build and device test |
| TestFlight | Managed beta testing before a wider release | Developer Program/App Store Connect setup, signed archive, upload and any required beta review |
| Signed ad hoc IPA | A controlled set of registered test devices | Matching distribution profile and an actual signed export; include the extension |
| App Store | Possible later public release | Complete acceptance, accurate privacy/product information and Apple's review; approval is not guaranteed |
| Authorized alternative marketplace or Web Distribution | Supported regional distribution after eligibility and review | Set up the chosen Apple-authorized route and obtain notarized distribution assets; not configured in this repository |

Apple provides [alternative distribution in supported regions](https://developer.apple.com/distribute/) and specifically [Web Distribution in the EU](https://developer.apple.com/support/web-distribution-eu/). These routes have their own account, region, supported-OS and authorization requirements; they still involve Apple's signing/notarization process. A normal downloadable unsigned IPA is not that process. No marketplace, web-distribution registration or notarization submission has been performed for Weiktube. Review the current official requirements before selecting a route rather than treating a source ZIP or unsigned archive as an installable release.

## Acceptance still needed on hardware

Confirm original YouTube playback and website navigation, mini/fullscreen transitions without restart, orientation and audio ownership, native public-media playback, system PiP, Share Extension import, OAuth reconnect/revocation and consented account actions on the intended iPhone/iPad. Network-dependent filters, SponsorBlock, RYD and YouTube UI behavior require live acceptance. Keep compiler/test results and device observations separate when recording status.

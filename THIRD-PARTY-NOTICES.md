# Third-party notices

## Weiktube Android and this native iOS port

This repository is a derivative native port of **weikiboy-tech/Weiktube**, reference
version **1.3.23**, commit **a7e0a9221e73d3d9c361f614adcb9e027fb70c35**.
The Android project's `THIRD-PARTY-NOTICES.md` explicitly designates its source
**GPL-3.0-only**. This port retains that license, its full `LICENSE`, and the
original artwork, filter-source notices and attribution. Source authors and
contributors retain their respective copyrights. New Swift, JavaScript adaptation,
project and test files created for this port are GPL-3.0-only.

Android source and history: https://github.com/weikiboy-tech/Weiktube/tree/a7e0a9221e73d3d9c361f614adcb9e027fb70c35

The app icon is rendered from the original Android `ic_weiktube.xml` paths and
colors. The deterministic renderer is `scripts/generate-icons.py`. No third-party
brand ownership is claimed. YouTube and Google marks belong to their owners.

## AdGuard Scriptlets 2.5.1 and filter rules

Copyright **Adguard Software Ltd. and contributors**, GPL-3.0.
Only selected pinned scriptlets are used: set-constant, json-prune,
json-prune-fetch-response and json-prune-xhr-response. The original Weiktube
transformations disable response logging and count actual removals. The iOS
adapter installs them through supported WebKit user scripts.

- Upstream: https://github.com/AdguardTeam/Scriptlets/tree/v2.5.1
- Rule basis: https://github.com/AdguardTeam/AdguardFilters/blob/master/BaseFilter/sections/specific.txt
- Exact licensing/provenance: `Weiktube/Resources/Filters/PROVENANCE.md`
- Bundled license: `Weiktube/Resources/Filters/ADGUARD-LICENSE.txt`
- Exact upstream package/source archives and deterministic generator:
  `Weiktube/AdBlock/VendorSource/`

Vendor source archives are provided with the source distribution, **not** copied
into the app bundle. `node Weiktube/AdBlock/VendorSource/vendor-adblock.mjs --check`
verifies the pinned inputs and generated scriptlet output. Filter updates carry
strictly constrained signed data, never remotely supplied executable scripts.

## SponsorBlock community data

SponsorBlock data is supplied by https://sponsor.ajay.app/ under
**Creative Commons Attribution-NonCommercial-ShareAlike 4.0**. The data license is
separate from the GPL source-code license. The app validates and displays segment
data and keeps local skip statistics. No SponsorBlock browser-extension code or
voting/submission implementation is included.

- Data/API license: https://github.com/ajayyy/SponsorBlock/wiki/Database-and-API-License
- License: https://creativecommons.org/licenses/by-nc-sa/4.0/
- Attribution and privacy appear in the SponsorBlock settings.

## Return YouTube Dislike

Optional public estimated dislike counts are read from
https://returnyoutubedislike.com/. No extension source or voting algorithm is
bundled, and these numbers are not represented as official YouTube figures.

- Upstream: https://github.com/Anarios/return-youtube-dislike
- Usage information: https://www.returnyoutubedislike.com/docs/usage-rights

## Apple and Google interfaces

SwiftUI, UIKit, WebKit, AVFoundation, AVKit, AuthenticationServices, Security,
AppIntents, MediaPlayer and other system frameworks are Apple platform components
and are used under the platform SDK terms. Swift's system/runtime components retain
their upstream notices. The app does not bundle GeckoView, AndroidX, Kotlin,
Google Play services, Flutter or React Native.

Google OAuth and YouTube Data API access use official HTTPS endpoints and a real
registered iOS OAuth client supplied by the developer. No Google SDK source is
bundled. Service use and distribution require review under the applicable service
terms; copying source licenses does not confer rights to third-party content.

No private keys, Apple certificates, Google secrets, account tokens, browser cookies
or device captures are included in this source distribution.

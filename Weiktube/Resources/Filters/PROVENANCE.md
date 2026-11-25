# Weiktube iOS filter provenance

Android reference: `weikiboy-tech/Weiktube`, commit
`a7e0a9221e73d3d9c361f614adcb9e027fb70c35` (1.3.23).

`rules.json`, `rules.sig` and `update-public-key.txt` are copied byte for byte from
`content-filter/src/main/assets/weiktube-adblock/` at that reference. Their RSA
SHA-256 signature is verified before parsing. Updates come only from the existing
`adblock-rules-v1` release, use the same pinned public verification key, reject
version rollback and are compiled before replacing the active WebKit rule list.
Remote packages cannot supply executable code, arbitrary selectors or arbitrary
CDN/credential-domain blocks. A failed update retains the previous valid rules.

AdGuard Scriptlets **2.5.1**, GPL-3.0, copyright Adguard Software Ltd. and
contributors. Upstream: <https://github.com/AdguardTeam/Scriptlets/tree/v2.5.1>.
The license is `ADGUARD-LICENSE.txt`. Exact published archive, readable module,
corresponding tagged source archive, package metadata and deterministic generator
are retained in `Weiktube/AdBlock/VendorSource/` in this source distribution. They
are not application resources. Run:

```sh
node Weiktube/AdBlock/VendorSource/vendor-adblock.mjs --check
```

Only `set-constant`, `json-prune`, `json-prune-fetch-response` and
`json-prune-xhr-response` are included. The original Weiktube generator silences
response/body diagnostics, propagates installation errors and counts actual
pruning mutations rather than hook installations. The iOS generator changes
source/output paths and provenance comments; implementation remains the reviewed
Android-generated subset.

`filter-runtime-ios.js` derives from the Android GPL-3.0-only runtime. iOS changes:
use `window.webkit.messageHandlers.weiktubeAdEvents`; allow validated YouTube
embed frames and `youtube-nocookie.com`. All bridges treat messages as untrusted,
bounded diagnostics, validate frame origin and instance token, and never use them
as authorization signals. The runtime does not extract cookies, credentials or
protected streams. A recognized ad is paused and covered, without forced seeking
or simulated visibility. This can require an explicit user retry or filter
disable when YouTube changes behavior; uninterrupted ad-free playback is not
guaranteed.

Network and cosmetic rules are translated to `WKContentRuleList`. WebKit offers
no public per-request block counter, so the app does not invent network-block
statistics. Runtime counts are separately labeled page-observed diagnostics.
Scriptlet property traps cannot be safely removed from a live document: changing
filters shows that a user-requested reload is needed for already open pages.

The original YouTube rule subset derives from the GPL-3.0 AdGuard BaseFilter
YouTube section reviewed on 2026-11-04:
<https://github.com/AdguardTeam/AdguardFilters/blob/master/BaseFilter/sections/specific.txt>.
It is not the entire AdGuard application or filtering engine. DRM endpoints,
normal media segments and creator sponsorships are excluded from this filter.

SponsorBlock integration consumes community data, not extension code. Data:
<https://sponsor.ajay.app/> under CC BY-NC-SA 4.0. Attribution and database/API terms:
<https://github.com/ajayyy/SponsorBlock/wiki/Database-and-API-License>.
Return YouTube Dislike estimates are attributed to
<https://returnyoutubedislike.com/>; usage terms:
<https://www.returnyoutubedislike.com/docs/usage-rights>.

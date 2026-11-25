# Android-Referenz und vollständiges Funktionsinventar

Stand: 25. November 2026. Das Original ist **weikiboy-tech/Weiktube**, Version **1.3.23**, versionCode **40**. Gepinnter Commit: **`a7e0a9221e73d3d9c361f614adcb9e027fb70c35`**, veröffentlicht als „Publish Weiktube 1.3.23 with player stability fixes“.

- [Unveränderliche Quellreferenz](https://github.com/weikiboy-tech/Weiktube/tree/a7e0a9221e73d3d9c361f614adcb9e027fb70c35)
- [Android-App-Konfiguration](https://github.com/weikiboy-tech/Weiktube/blob/a7e0a9221e73d3d9c361f614adcb9e027fb70c35/app/build.gradle.kts)
- [Historischer 1.3.23-Releasebericht](https://github.com/weikiboy-tech/Weiktube/blob/a7e0a9221e73d3d9c361f614adcb9e027fb70c35/RELEASE-1.3.23.md)
- [iOS-Paritätsmatrix mit allen 163 Android-IDs](FEATURE-PARITY.md)

Die Originalquelle wurde als schreibgeschützte Vergleichsbasis behandelt. In dieser Arbeit wurde kein neuer Android-Emulator-, Geräte- oder Gradle-Testlauf durchgeführt. Das folgende vollständige Quellcodeprotokoll enthält **163 Funktionszeilen** einschließlich exakter Dateipräfixe, Android-Testquellen, Einstellungen, gespeicherter Daten, Lizenzen und historischer Regressionen. Historische Ergebnisse werden ausdrücklich nicht als heutiger grüner Baseline-Lauf übernommen.

Der iOS-Quellcode wird im öffentlichen Repository [weikiboy-tech/Weiktube-ios](https://github.com/weikiboy-tech/Weiktube-ios) auf dem Branch `main` entwickelt.

## Wesentliche Entscheidungen für die Portierung

Die Hauptstartseite ist im aktuellen Android-Code die originale YouTube-Website über Gecko, nicht der ältere native PersonalHomeFeed. Die iOS-App behält dieses Websitekonzept mit WKWebView bei. Home, Watch und Shorts sind unabhängige behaltene Dokumente mit einem zentralen hörbaren Besitzer. Die geometrische Darstellung des Players darf seine Medienquelle nicht austauschen.

Google-API-Freigabe und Websitekonto sind bereits auf Android getrennt. iOS benötigt eine neue registrierte iOS-OAuth-Konfiguration und Systemauthentifizierung; Android-Client-IDs oder Website-Cookies werden nicht übertragen. Konto-Parität umfasst auch Likes, Aboänderungen, Kommentare/Antworten und Speichern in Playlists. Öffentliche direkte HTTPS-Medien sind eine bestehende Android-Funktion; AVPlayer dafür ist eine Plattformanpassung, keine YouTube-Stream-Extraktion.

SponsorBlock und RYD sind ursprünglich ausgeschaltet. Die acht SponsorBlock-Modi/Farben und die Cache-/Ratelimits wurden explizit geprüft. AdBlock besteht aus signierten Daten, Netzwerkregeln, gezielten Scriptlets, kosmetischen Selektoren und erkanntem Werbezustand; ein bloßer Domainfilter würde wesentliche Originalfunktion weglassen.

Die zugängliche iOS-Ausführung, Signierung, App Group, Share Extension, App Intents, System-PiP, Safe Areas und iPad-Fenster sind zusätzliche Prüfaufgaben. Androids letzte Releaseberichte lassen insbesondere visuelle Mini-/Playerabnahme noch offen. Deshalb wird weder die Android-Referenz noch die neue iOS-App pauschal als vollständig praktisch bestätigt dargestellt.

## Vollständiges Referenzprotokoll

Das nachfolgende englischsprachige Audit ist das während der Quellprüfung erstellte vollständige Inventar. Die deutschen iOS-Statusbewertungen stehen separat in `FEATURE-PARITY.md`; die Android-Evidenzspalte dieses Protokolls beschreibt vorhandene Testquellen oder historische Angaben, keine neu ausgeführten Tests.

## Audit: Weiktube Android 1.3.23

## Reference and evidence level

Reference repository: https://github.com/weikiboy-tech/Weiktube. The reference checkout was read-only. Reference HEAD: **`a7e0a9221e73d3d9c361f614adcb9e027fb70c35`**, dated 2026-11-25 10:04:40 +01:00, subject “Publish Weiktube 1.3.23 with player stability fixes”. `app/build.gradle.kts` declares **versionName 1.3.23, versionCode 40**, minSdk 26, targetSdk 36, compileSdk 37. Three modules: `app`, `home-data`, `content-filter`.

This is a source audit, **not a new Android test run or an iOS acceptance result**. Historical release reports are evidence of what their authors tested at that point; they do not prove current device behavior. In particular `RELEASE-1.3.23.md` explicitly leaves the OnePlus 15R visual acceptance open. `RELEASE-1.3.22.md` reports 305/307 tests in its final full app run and isolated retries passing; do not silently translate that into a completely green baseline.

Production Kotlin inventory: `app` 60 files; `home-data` 21; `content-filter` 4. Test source inventory: `app` 45 files (303 literal `@Test` annotations); `home-data` 12 (78); `content-filter` 1 (20). Annotation totals are a source count, not execution results (parameterized cases can differ).

All source references below are relative to the Android repository at the pinned commit. Prefixes are exact:

- `A/` = `app/src/main/java/com/weiktube/app/`
- `H/` = `home-data/src/main/java/com/weiktube/home/`
- `F/` = `content-filter/src/main/java/com/weiktube/filter/`
- `AT/` = `app/src/test/java/com/weiktube/app/`
- `HT/` = `home-data/src/test/java/com/weiktube/home/`
- `FT/` = `content-filter/src/test/java/com/weiktube/filter/`
- `S/` = `scripts/`

## Critical implementation findings

1. The current main Home tab embeds the **original YouTube website through `OriginalHomeController`**, despite the legacy `isPersonalHome` name. The native `PersonalHomeScreen` (subscriptions plus history) remains in source but is not the current main Home UI. Replacing Home with an API feed would miss the requested behavior.
2. Android has **three independently retained web surfaces**: Gecko Home, WebView watch player, and lazily created WebView Shorts; an auxiliary browser is also retained. Playback ownership prevents Home/previews, Shorts, and the watch player from sounding together. Healthy documents are not recreated for presentation changes.
3. Native Google API authorization and website sign-in are **separate accounts/sessions**. Android native authorization uses official Google Play authorization with `youtube.readonly`, escalating to `youtube.force-ssl` only for explicit interaction consent. Tokens never enter a WebView. iOS needs a new registered OAuth client, not an invented Android-client substitution.
4. Account parity includes **like/unlike, subscribe/unsubscribe, comment reading, replies, posting comments/replies, and saving to an existing own playlist**, in addition to reading subscriptions/playlists. These are easy to overlook. The native action sheet does not contain a separate native “dislike vote” button; the website retains that action.
5. Direct public HTTPS video URLs are an existing supported feature. YouTube/CDN extraction URLs are explicitly rejected. An AVPlayer route for genuinely public direct media is therefore parity, not an invented replacement YouTube player.
6. Advanced single-finger gestures operate in **expanded landscape**; portrait downward drag is reserved for minimization. Pinch is supported in expanded portrait and landscape. Pinch limits are **1–8×**; there is no saved Android zoom preference.
7. Android quality selection is capability-probed and explicitly described as based on **unguaranteed mobile website internals**. The public IFrame API does not provide equivalent forced quality control. Do not claim quality success just because preferences save.
8. AdBlock is a combination of domain blocking, YouTube request rules, pinned AdGuard scriptlets, cosmetic filtering, and recognized-ad handling. It is not only a static host list. Its protected reload is bounded to one attempt per video.
9. SponsorBlock and RYD are **disabled by default with consent before first enable**. SponsorBlock uses a four-hex-character SHA-256 prefix and locally filters the bucket for the exact video ID. RYD sends the public full video ID. Their network clients are isolated from OAuth/cookies.
10. An unchanged DOM/video identity is not proof of uninterrupted playback. Historical YouTube-driven pauses were observed despite retained nodes and correct geometry; those must remain an acceptance concern on iOS.

## Exact visual identity

| Token | Android value | Source |
| --- | --- | --- |
| Primary mint | `#65D8C8` | `A/WeiktubeUi.kt` |
| Dark background/surface | `#0F0F0F` | `A/WeiktubeUi.kt` |
| Dark cards / high cards | `#212121` / `#272727` | `A/WeiktubeUi.kt` |
| Dark secondary | `#AAAAAA` | `A/WeiktubeUi.kt` |
| Light background/surface | white | `A/WeiktubeUi.kt` |
| Light primary | `#006B60` | `A/WeiktubeUi.kt` |
| Light cards / high cards | `#F2F2F2` / `#EAEAEA` | `A/WeiktubeUi.kt` |
| Light secondary | `#606060` | `A/WeiktubeUi.kt` |
| Progress red | `#FF0033` (`#f03` in Shorts) | `A/WeiktubeUi.kt`, `A/ShortsAudioScript.kt` |
| Logo artwork | 108×108; background `#10151D`; mint polygon `M27,28L44,38L44,70L27,80Z` plus triangle `M49,28L83,54L49,80Z` | `app/src/main/res/drawable/ic_weiktube.xml` |
| Header | 52dp height; 12dp horizontal padding; 28dp logo; 6dp logo/title gap | `A/WeiktubeUi.kt` |
| Bottom navigation | 60dp high; 24dp rounded icons; always visible small labels; no colored indicator pill | `A/WeiktubeUi.kt` |
| Tab order/icons | Startseite/Home; Shorts/SlowMotionVideo; Adblock/Shield; Abos/Subscriptions; Du/AccountCircle | `A/WeiktubeUi.kt` |
| Mini card | bottom trailing; max width 196dp, screen width minus 24dp; 12dp edges/corner radius; 8dp shadow; 16:9 outer card | `A/WeiktubeUi.kt` |
| Mini animation | one 180ms tween drives geometry, radius, navigation space; reversible | `A/WeiktubeUi.kt` |
| Mini controls | 48dp touch target with 32dp translucent black circle; play/pause and close; red 2dp bottom progress | `A/WeiktubeUi.kt` |
| Player accessory row | 44dp high; minimize, title, account actions, share, PiP, close | `A/WeiktubeUi.kt` |
| History carousel | 12 entries; cards 208dp wide; 12dp radius; 16:9 thumbnail; 12dp gap | `A/PersonalHomeUi.kt`, `A/RecentHistoryUi.kt` |
| Subscription channel carousel | 72dp cells, 60dp round avatars, 14dp gap | `A/SubscriptionsUi.kt` |
| Subscription video cards | full width 16:9 thumbnail; duration at bottom trailing; 38dp avatar; 12dp text inset | `A/SubscriptionsUi.kt` |
| Settings cards | typically 16dp padding, 10dp vertical gap; shield hero 20dp | `A/PlayerSettings.kt`, `A/SponsorBlockUi.kt`, `A/WeiktubeUi.kt` |

Native Apple symbols may be used for matching rounded metaphors, but logo paths/colors should come directly from the existing vector asset. Material typography is semantic, not a set of fixed font sizes; preserve hierarchy while supporting Dynamic Type.

## Complete actionable feature inventory

The final iOS parity matrix should preserve the individual IDs below, add iOS file/test references, and use the user's requested status vocabulary. “Android test evidence” means a source test or documented historical test exists, not that it was rerun in this audit.

### Navigation, Home, and browsing

| ID | Existing Android behavior | Android implementation | Android test evidence / qualification |
| --- | --- | --- | --- |
| NAV-01 | Five bottom tabs in order Startseite, Shorts, Adblock, Abos, Du | `A/WeiktubeUi.kt`, `A/MainActivity.kt` | `AT/HomeRoutePolicyTest.kt`; real navigation acceptance still required |
| NAV-02 | Menu entries open video link, history, settings/updates, reload current web page | `A/WeiktubeUi.kt` | UI/device coverage in `TESTING.md` |
| NAV-03 | Header search routes to original YouTube search; account icon opens Du | `A/MainActivity.kt`, `A/BrowserController.kt` | `S/check-browser-scripts.cjs` |
| NAV-04 | Back order: native full screen, Shorts return-to-Home, expanded player minimize, page history/search, home tab, close mini | `A/MainActivity.kt` | `AT/PlayerControllerLifecycleTest.kt`, `S/check-watch-navigation.cjs` |
| NAV-05 | Tab and page state retained; selecting current Home explicitly goes Home, changing back to Home does not unnecessarily reload | `A/MainActivity.kt`, `A/WeiktubeUi.kt`, `H/OriginalHomeController.kt` | `HT/OriginalHomeTabBackgroundTest.kt`, `S/check-original-home-navigation.cjs` |
| NAV-06 | HTTPS external navigation to external app/browser without reentering Weiktube | `A/MainActivity.kt` | `AT/LinksTest.kt` |
| HOME-01 | Original responsive YouTube Home embedded in main tab | `H/OriginalHomeController.kt` | `S/check-home-cold-start.mjs`, historical `RELEASE-1.3.2.md` |
| HOME-02 | Personalized original recommendations when website has its own valid sign-in | `H/HomeEngine.kt`, `H/WebsiteAccountSetup.kt` | `HT/WebsiteAccountSetupTest.kt`; native OAuth alone never proves this |
| HOME-03 | First visible, dismissible website account setup; later entry under Du; account host/origin shown | `H/WebsiteAccountSetup.kt`, `H/OriginalHomeController.kt`, `A/HomeConnectionEntry.kt` | `HT/WebsiteAccountSetupTest.kt` |
| HOME-04 | Channels, playlists, search results, ordinary website navigation in retained Home document | `H/OriginalHomePolicy.kt`, `H/OriginalHomeController.kt` | `HT/OriginalHomePolicyTest.kt` |
| HOME-05 | Trusted video card click/pointer or bounded SPA navigation handoff to watch; Shorts retain Shorts route | `home-data/src/main/assets/original-home-navigation/bridge.js`, `H/OriginalHomeController.kt` | `S/check-original-home-navigation.cjs`, `HT/OriginalHomeBridgeActivationTest.kt` |
| HOME-06 | Return to same retained Home page and scroll after watch/minimize; one-time route grant prevents duplicate launches | `H/OriginalHomeReturn.kt`, `H/OriginalHomeReturnPolicy.kt`, `H/OriginalHomeBridgeActivation.kt` | `HT/OriginalHomeReturnPolicyTest.kt`, `S/check-gecko-return-lifecycle.py` |
| HOME-07 | Home media is paused/muted so videos play only through active watch/Shorts owner | `home-data/src/main/assets/original-home-navigation/bridge.js`, `H/OriginalHomeController.kt` | `S/check-original-home-navigation.cjs` |
| HOME-08 | Hidden retained Home may finish already allowed nonvideo navigation; cannot initiate web playback/auth | `H/OriginalHomeTabBackground.kt` | `HT/OriginalHomeTabBackgroundTest.kt` |
| HOME-09 | Previously visible website authentication may complete while authenticator is foreground; narrow challenge subframes | `H/OriginalHomeBackground.kt`, `H/OriginalHomePolicy.kt` | `HT/OriginalHomeBackgroundTest.kt` |
| HOME-10 | Website profile persists independently of native OAuth; clearing cookies/web data clears it | `H/HomeEngine.kt`, `A/MainActivity.kt` | `HT/HomeContentRecoveryTest.kt`; no cookie extraction |
| HOME-11 | Startup opens blank Gecko session before awaiting blocker extension readiness, avoiding cyclic startup dependency | `H/HomeEngine.kt`, `H/OriginalHomeController.kt`, `H/GeckoAdBlock.kt` | `S/check-home-cold-start.mjs`, `RELEASE-1.3.7.md`; technology-specific implementation should not port literally |
| HOME-12 | Safe error/status/retry and ownership-aware recovery after content crash/kill | `H/HomeContentRecovery.kt`, `H/OriginalHomeController.kt` | `HT/HomeContentRecoveryTest.kt` |
| HOME-13 | Public search suggestions/results remain YouTube's original interface | `A/BrowserController.kt`, `A/MainActivity.kt` | `S/check-browser-scripts.cjs`; no unofficial suggestion service |
| HOME-14 | Auxiliary HTTPS browser plus local Shields test surface | `A/BrowserController.kt`, `A/MainActivity.kt` | `AT/ShieldEngineTest.kt`; not the primary Home design |
| HOME-15 | Separate native system autofill suggestion button on eligible website auth field, with stale-target checks | `H/OriginalHomeAutofill.kt`, `H/OriginalHomeAutofillPolicy.kt` | `HT/OriginalHomeAutofillPolicyTest.kt`; iOS should use supported system authentication/autofill without credential capture |

### Watch player, lifecycle, full screen, and PiP

| ID | Existing Android behavior | Android implementation | Android test evidence / qualification |
| --- | --- | --- | --- |
| PLAY-01 | One retained watch WebView and existing YouTube watch video; same video selection expands/resumes without reload | `A/PlayerController.kt` | `AT/PlayerControllerLifecycleTest.kt`, `S/check-player-scripts.cjs` |
| PLAY-02 | Play/pause from website, native mini, PiP; explicit play and pause commands, not stale toggles | `A/PlayerController.kt`, `A/NativePipController.kt`, `A/WeiktubeUi.kt` | `AT/NativePipControllerTest.kt`, `AT/PlayerPlaybackObserverTest.kt` |
| PLAY-03 | Position/duration/progress tracked without replacing valid position with empty/loading DOM zero | `A/PlayerController.kt`, `A/PlayerProgress.kt` | `AT/PlayerProgressTest.kt`, `AT/PlayerDocumentLifecycleTest.kt` |
| PLAY-04 | Original YouTube interactive timeline, seek, captions, speed menu, quality menu, metadata/recommendations | `A/PlayerController.kt` (`WATCH_CHROME`) | `S/check-player-layout.cjs`; options depend on YouTube/content; no independent native caption implementation exists |
| PLAY-05 | Public direct HTTPS media in controlled HTML5 video document with native HTML controls | `A/PlayerController.kt`, `A/Links.kt` | `AT/LinksTest.kt`, player lifecycle fixtures; no YouTube/googlevideo extraction allowed |
| PLAY-06 | One audible owner: switch to Shorts pauses watch; opening watch pauses Shorts/browser; hidden surfaces cannot autoplay | `A/MainActivity.kt`, `A/WeiktubeUi.kt`, `A/PlayerController.kt`, `A/BrowserController.kt` | `AT/PlayerModeContinuityTest.kt`, `S/check-player-scripts.cjs` |
| PLAY-07 | One explicit selection requests audible start; subsequent mute/pause remains respected | `A/PlayerController.kt` (`MEDIA_GUARD`) | `S/check-player-audio.cjs`, `docs/HISTORY-PIP-AUDIO-REVIEW.md` |
| PLAY-08 | Loading/error/retry states, retry retains selected position and expanded state | `A/PlayerController.kt`, `A/WeiktubeUi.kt` | `AT/PlayerControllerLifecycleTest.kt` |
| PLAY-09 | Video-origin portrait downward drag minimizes; back and arrow share same route | `A/PlayerDragGesture.kt`, `A/PlayerGestureLayout.kt`, `A/MainActivity.kt` | `AT/PlayerDragGestureTest.kt` |
| PLAY-10 | Mini overlay bottom trailing, browse app while continuing, tap expands, play/pause/close/progress/error retry | `A/WeiktubeUi.kt`, `A/PlayerController.kt` | `AT/PlayerStableViewportTest.kt`, `AT/PlayerModeContinuityTest.kt`, `S/check-player-layout.cjs` |
| PLAY-11 | Shared interruptible 180ms geometry transition; measured video bounds/aspect are start rectangle | `A/WeiktubeUi.kt`, `A/PlayerViewportTransform.kt` | `AT/PlayerTransitionTest.kt`, `AT/PlayerStableViewportTest.kt`; real motion unaccepted in 1.3.23 |
| PLAY-12 | Mini/PiP retains logical watch viewport; transforms native host instead of repeatedly reflowing tiny document | `A/PlayerGestureLayout.kt`, `A/PlayerViewportTransform.kt` | `AT/PlayerStableViewportTest.kt`, `S/check-player-layout.cjs` |
| PLAY-13 | Portrait/landscape full-screen rendering, correct safe-area/inset delivery, return restores portrait document positioning | `A/MainActivity.kt`, `A/PlayerGestureLayout.kt`, `A/PlayerController.kt` | `AT/PlayerViewportInsetsTest.kt`, `S/check-player-layout.cjs` |
| PLAY-14 | Both landscape sides; upside-down ignored; sensor hysteresis avoids diagonal chatter | `A/UprightVideoOrientation.kt`, `A/MainActivity.kt` | `AT/UprightVideoOrientationTest.kt` |
| PLAY-15 | Full-screen button matches actual app landscape mode; trusted web full-screen click goes to native controller | `A/WatchNavigationScript.kt`, `A/MainActivity.kt`, `A/PlayerController.kt` | `S/check-watch-navigation.cjs`, `AT/PlayerControllerLifecycleTest.kt` |
| PLAY-16 | Manual exit held until posture changes between upright and sideways or expanded session ends | `A/MainActivity.kt` (`orientationChoice`) | `AT/PlayerControllerLifecycleTest.kt`, `RELEASE-1.3.23.md` |
| PLAY-17 | Minimize/close releases owned fullscreen surface; stale fullscreen callbacks cannot cover new player | `A/MainActivity.kt`, `A/PlayerController.kt` | `AT/PlayerControllerLifecycleTest.kt`, `docs/PLAYER-STABILITY.md` |
| PLAY-18 | Native Android system PiP automatic on leaving app if eligible and playing; manual entry if playable | `A/NativePipController.kt`, `A/MainActivity.kt` | `AT/NativePipControllerTest.kt`, `S/check-native-pip-integration.cjs`; iOS equivalent must use Apple APIs |
| PLAY-19 | PiP aspect and source rectangle from visible contained video; returning coordinates retained while floating | `A/NativePipController.kt`, `A/MainActivity.kt` | `AT/NativePipControllerTest.kt`, `RELEASE-1.3.23.md` |
| PLAY-20 | PiP play/pause action tied to source and token; expanding PiP does not automatically play/close | `A/NativePipController.kt` | `AT/NativePipControllerTest.kt` |
| PLAY-21 | No invisible background playback: screen lock/host stop pauses; visible PiP may continue; resume does not override pause | `A/MainActivity.kt`, `A/PlayerController.kt` | `AT/MainActivityScreenStateTest.kt`, `AT/PlayerModeContinuityTest.kt` |
| PLAY-22 | Keep screen awake only while active playback; release wake flags when stopped | `A/MainActivity.kt`, `A/WeiktubeUi.kt` | screen-state tests and manual acceptance |
| PLAY-23 | One bounded recovery after actual renderer loss; restore source/position/presentation/play intent; new selection/close wins | `A/PlayerController.kt` | `AT/PlayerControllerLifecycleTest.kt` |
| PLAY-24 | Slow renderer is not killed/reloaded by timeout; confirmed lost empty document permits one recovery | `A/PlayerController.kt` | `AT/PlayerDocumentLifecycleTest.kt` |
| PLAY-25 | Document generation and view identity reject late metadata, error, full-screen, enhancement, and JS callbacks | `A/PlayerController.kt`, `A/PlayerPlaybackObserver.kt` | `AT/PlayerDocumentLifecycleTest.kt`, `AT/PlayerControllerLifecycleTest.kt` |
| PLAY-26 | Process/activity recreation restores saved selection minimized and paused, new external link takes precedence | `A/MainActivity.kt`, `A/PlayerController.kt` | `AT/PlayerResumeSelectionTest.kt`, `AT/ExternalYoutubeIntentTest.kt` |
| PLAY-27 | Player share action uses selected public URL | `A/MainActivity.kt`, `A/WeiktubeUi.kt` | manual sharing acceptance |
| PLAY-28 | Account action sheet pauses current player while shown and never silently resumes user pause | `A/WeiktubeUi.kt`, `A/VideoActionsUi.kt` | `AT/VideoReadReloadGateTest.kt`, lifecycle tests |

### Advanced gestures and quality

| ID | Existing Android behavior | Android implementation | Android test evidence / qualification |
| --- | --- | --- | --- |
| GEST-01 | Two-finger pinch 1–8×, video pixels only, focused around pinch center with bounded translation | `A/VideoZoomScript.kt`, `A/PlayerGestureLayout.kt` | `AT/PlayerVideoZoomGestureTest.kt`, `S/check-video-zoom.cjs`, `S/check-video-zoom-layout.cjs` |
| GEST-02 | Zoom-to-fill emerges from scale/contain calculation; UI/controls/captions don't scale | `A/VideoZoomScript.kt` | `S/check-video-zoom-layout.cjs` tests 16:9, 4:3, 9:16, 1:1 |
| GEST-03 | Reset zoom on mini/PiP/source/rotation/resize; no reload or media command; restore prior inline styles | `A/PlayerController.kt`, `A/VideoZoomScript.kt` | `AT/PlayerVideoZoomGestureTest.kt`, zoom JS tests |
| GEST-04 | Pinch cancels single-finger gesture; leftover finger never starts drag/seek/hold | `A/PlayerGestureLayout.kt`, `A/AdvancedPlayerGesture.kt` | `AT/AdvancedPlayerIntegrationTest.kt`, `AT/PlayerVideoZoomGestureTest.kt` |
| GEST-05 | Left vertical landscape gesture adjusts window brightness 2–100%, percent HUD, restores baseline on exit/focus loss | `A/PlayerWindowControls.kt`, `A/PlayerGestureLayout.kt` | `AT/AdvancedPlayerGestureTest.kt` |
| GEST-06 | Right vertical landscape gesture controls music volume 0–100%, percent HUD, honors fixed-volume restrictions | `A/PlayerWindowControls.kt` | `AT/AdvancedPlayerGestureTest.kt`; platform-specific public alternative needed on iOS |
| GEST-07 | Double tap left/right seeks chosen 5/10/15/20/30s; repeated same-side taps accumulate actual achieved time | `A/AdvancedPlayerGesture.kt`, `A/AdvancedPlayerScript.kt`, `A/PlayerController.kt` | `AT/AdvancedPlayerGestureTest.kt`, `S/check-advanced-player.cjs` |
| GEST-08 | Seek clamps to finite duration and playable seek ranges, no implicit play/pause | `A/AdvancedPlayerScript.kt` | `S/check-advanced-player.cjs` |
| GEST-09 | Hold temporary rate, default 2×; only reported supported 1.5/2/2.5/3×; paused video not started | `A/AdvancedPlayerScript.kt`, `A/PlayerPreferences.kt` | `S/check-advanced-player.cjs`, `AT/PlayerPreferencesTest.kt` |
| GEST-10 | Hold restores exact former rate on release/cancel/second pointer/focus/rotation/mini/PiP/source/background | `A/AdvancedPlayerScript.kt`, `A/PlayerGestureLayout.kt`, `A/MainActivity.kt` | `AT/AdvancedPlayerIntegrationTest.kt`, `S/check-advanced-player.cjs` |
| GEST-11 | Controls, timeline, menus and horizontal motion excluded; uncertain async hit test passes to website within 120ms | `A/AdvancedPlayerGesture.kt`, `A/AdvancedPlayerScript.kt` | `AT/AdvancedPlayerGestureTest.kt`, `S/check-advanced-player-dom.cjs` |
| GEST-12 | Portrait minimize threshold 64dp or ≥24dp plus ≥900dp/s down; raw screen coordinates; 1.25× vertical direction ratio | `A/PlayerDragGesture.kt`, `A/PlayerGestureLayout.kt` | `AT/PlayerDragGestureTest.kt` |
| QUAL-01 | Separate saved preferred quality for Wi-Fi and cellular/metered; default1080/720; unknown network Auto | `A/PlayerPreferences.kt`, `A/PlayerQuality.kt` | `AT/PlayerPreferencesTest.kt` |
| QUAL-02 | Choices Auto,144,240,360,480,720,1080,1440,2160 filtered to current reported video capability | `A/PlayerSettings.kt`, `A/PlayerQuality.kt` | `S/check-player-quality.cjs` |
| QUAL-03 | One request per new video for nearest lower available level; network changes apply next selection | `A/PlayerQuality.kt` | `S/check-player-quality.cjs` |
| QUAL-04 | Manual setting interactions stop automation; verify response for5s, probe ≤12 ticks, fail to honest automatic/unconfirmed status | `A/PlayerQuality.kt` | `S/check-player-quality.cjs`; undocumented YouTube website methods, actual success not guaranteed |

### Shorts

| ID | Existing Android behavior | Android implementation | Android test evidence / qualification |
| --- | --- | --- | --- |
| SHORT-01 | Original Shorts vertical feed in its own retained lazy web surface | `A/BrowserController.kt`, `A/MainActivity.kt` | `S/check-shorts-audio.cjs`, `AT/ExternalYoutubeIntentTest.kt` |
| SHORT-02 | Shorts URLs including bare `/shorts/` route to Shorts; Home-origin return navigation preserved | `A/Links.kt`, `A/MainActivity.kt`, `H/OriginalHomePolicy.kt` | `AT/LinksRegressionTest.kt`, `HT/OriginalHomePolicyTest.kt` |
| SHORT-03 | Active media chosen by visible area excluding hidden/disconnected/inert elements | `A/ShortsAudioScript.kt` | `S/check-shorts-audio.cjs` |
| SHORT-04 | Identity combines visit, element, route and source; stale/prefetched media cannot receive seek/audio requests | `A/ShortsAudioScript.kt` | `S/check-shorts-audio.cjs` |
| SHORT-05 | One audible-start attempt per current video after ready/playable state; no unmute/play loop; local player only | `A/ShortsAudioScript.kt`, `A/BrowserController.kt` | `S/check-shorts-audio.cjs` |
| SHORT-06 | Explicit mute respected for current tab visit using session storage; new visit resets attempt policy | `A/ShortsAudioScript.kt` | `S/check-shorts-audio.cjs` |
| SHORT-07 | If browser denies audible autoplay, actual trusted “Ton einschalten” action; hide website unmute hint only when verified audible | `A/ShortsAudioScript.kt` | `S/check-shorts-controls-layout.cjs`; reported audible DOM state does not prove speakers emit sound |
| SHORT-08 | Red3px track/g gray background, 32px hit area above native bottom bar; event/rAF driven progress | `A/ShortsAudioScript.kt` | `S/check-shorts-controls-layout.cjs` |
| SHORT-09 | Timeline tap and horizontal drag; preview while dragging, one seek at release | `A/ShortsAudioScript.kt` | `S/check-shorts-controls-layout.cjs` |
| SHORT-10 | Seekable ranges revalidated, nearest point selected across gaps, avoid exact end; unknown duration disables | `A/ShortsAudioScript.kt` | `S/check-shorts-audio.cjs` |
| SHORT-11 | Vertical feed swipe, second pointer/cancel/rotation/media change cancel scrubbing, preserve user's pause | `A/ShortsAudioScript.kt` | `S/check-shorts-controls-layout.cjs` |
| SHORT-12 | Accessible slider role/value/disabled state; keyboard left/right/home/end | `A/ShortsAudioScript.kt` | Shorts DOM fixtures; VoiceOver/iOS real acceptance new |
| SHORT-13 | Tab/foreground ownership gates Shorts; AdBlock applies; no saved normal-player resume behavior for Shorts | `A/BrowserController.kt`, `A/PlayerController.kt`, `A/PlaybackProgressStore.kt` | `AT/PlaybackProgressStoreTest.kt`, Shorts script fixtures |

### AdBlock

| ID | Existing Android behavior | Android implementation | Android test evidence / qualification |
| --- | --- | --- | --- |
| AD-01 | Master Weiktube protection, YouTube ads/ad-domain toggle, tracking domain toggle | `A/WeiktubeModel.kt`, `A/WeiktubeUi.kt`, `A/ShieldEngine.kt` | `AT/ShieldEngineTest.kt`, `AT/ShieldBaselineRegressionTest.kt` |
| AD-02 | Own domains and exceptions accept plain domains/hosts rows/comments, reject ABP/EasyList; 256KiB cap | `A/ShieldEngine.kt`, `A/WeiktubeUi.kt` | `AT/ShieldEngineTest.kt` |
| AD-03 | Domain/subdomain matching; exceptions apply to top-level and resource; never blanket block YouTube media infrastructure | `A/ShieldEngine.kt`, `F/FilterSnapshot.kt` | `AT/ShieldBaselineRegressionTest.kt`, `FT/FilterPackageTest.kt` |
| AD-04 | YouTube-specific request list: doubleclick, googlesyndication, googleadservices, adservice.google; YouTube `/pagead/`, `/api/stats/ads` | `content-filter/src/main/assets/weiktube-adblock/rules.json`, `F/FilterSnapshot.kt` | `FT/FilterPackageTest.kt`, `S/check-adblock-scripts.cjs` |
| AD-05 | Pinned AdGuard2.5.1 `set-constant`, `json-prune`, fetch/XHR response pruning for reviewed ad fields | `content-filter/src/main/assets/weiktube-adblock/vendor-scriptlets.js`, `filter-runtime.js`, `rules.json` | `S/vendor-adblock.mjs --check`, `S/check-adblock-scripts.cjs` |
| AD-06 | Explicit sponsored-renderer cosmetic selectors; counters increment actual changes, no body logging | `content-filter/src/main/assets/weiktube-adblock/filter-runtime.js` | `S/check-adblock-scripts.cjs` |
| AD-07 | Script injection at document start; each document pins verified policy/version; narrow origin/token bridge | `A/WebViewAdBlock.kt`, `H/GeckoAdBlock.kt` | `FT/FilterPackageTest.kt`, `S/test-gecko-adblock.mjs` |
| AD-08 | Recognized ad pauses/mutes/covers; watch gets ≤1 protected reload, then explicit failure; no ad-seeking or forcing | `A/PlayerController.kt`, `A/WebViewAdBlock.kt`, `filter-runtime.js` | `S/check-adblock-scripts.cjs`, `AT/PlayerControllerLifecycleTest.kt` |
| AD-09 | Protection across Home, browse/search, normal watch, Shorts; auth and media/DRM endpoints excluded | `F/FilterSnapshot.kt`, `A/BrowserController.kt`, `H/GeckoAdBlock.kt` | filter tests; no universal ad-free guarantee |
| AD-10 | Filter version/readiness/errors and counts of network blocks, removed ad data, hidden cosmetics, detected breakthroughs | `F/YoutubeAdBlock.kt`, `A/WeiktubeUi.kt` | filter script fixtures; iOS cannot pretend WKContentRuleList emits per-request counters |
| AD-11 | Clear session counters; local `.invalid` Shields test page | `A/BrowserController.kt`, `A/WeiktubeUi.kt` | `AT/ShieldEngineTest.kt`; on-device effect needs actual testing |
| AD-12 | Manual filter update check and ≤daily automatic attempt, serialized | `F/YoutubeAdBlock.kt` | `FT/FilterPackageTest.kt` |
| AD-13 | RSA SHA256 signature on exact data bytes before parsing, monotonic version/no rollback, atomic cache, bundled fallback | `F/SignedFilterPackage.kt`, `F/YoutubeAdBlock.kt` | `FT/FilterPackageTest.kt` |
| AD-14 | Strict schema/count/size/path/selector/scriptlet argument allowlists; remote updates carry data only, no executable code | `F/FilterSnapshot.kt` | `FT/FilterPackageTest.kt` |
| AD-15 | HTTPS allowlisted GitHub update origins, revalidate every redirect, byte/time/redirect bounds | `F/FilterUpdatePolicy.kt`, `F/YoutubeAdBlock.kt` | `FT/FilterPackageTest.kt` |
| AD-16 | Preserve GPL license/provenance for scripts/rules/generated transformations | `THIRD-PARTY-NOTICES.md`, `content-filter/src/main/assets/weiktube-adblock/PROVENANCE.md` | pinned source archive and deterministic generator in vendor/ |

### SponsorBlock and Return YouTube Dislike

| ID | Existing Android behavior | Android implementation | Android test evidence / qualification |
| --- | --- | --- | --- |
| SB-01 | Opt-in/consent, off by default, independent of ad filtering | `A/SponsorBlockUi.kt`, `A/SponsorBlockPreferences.kt` | `AT/SponsorBlockControllerTest.kt` |
| SB-02 | Four hex SHA256 prefix API bucket, exact ID filtering locally, read-only official service | `A/SponsorBlockSegment.kt`, `A/SponsorBlockClient.kt` | `AT/SponsorBlockClientTest.kt` |
| SB-03 | Eight categories with Auto/Manual/Off individually configurable | `A/SponsorBlockSegment.kt`, `A/SponsorBlockPreferences.kt`, `A/SponsorBlockUi.kt` | codec/controller tests; detailed defaults below |
| SB-04 | Automatic skip on active playback; manual button; no play/pause/load commands | `A/SponsorBlockScript.kt`, `A/SponsorBlockController.kt` | `S/check-sponsorblock.cjs`, `S/check-sponsorblock-dom.cjs` |
| SB-05 | Merge overlapping/touching eligible segments into one seek/count | `A/SponsorBlockScript.kt` | SponsorBlock JS fixtures |
| SB-06 | Require seekable range, ready media, stable video identity, matching duration within1s; no live/ad skips; missing duration downgrades Auto to Manual | `A/SponsorBlockScript.kt`, `A/SponsorBlockSegment.kt` | SponsorBlock JS/JVM fixtures |
| SB-07 | Seek attempt once/segment/session, confirm actual seeked within350ms position tolerance/2s deadline; no loops | `A/SponsorBlockScript.kt` | SponsorBlock JS fixtures |
| SB-08 | Notice (8s) with Undo; manual backward seeking suppresses immediate re-skip; undo adjusts statistics once | `A/SponsorBlockScript.kt`, `A/SponsorBlockStatistics.kt` | `AT/SponsorBlockStatisticsTest.kt`, SponsorBlock JS fixtures |
| SB-09 | Colored noninteractive segment layer only in recognized valid original timeline; separate marker capability status | `A/SponsorBlockScript.kt` | `S/check-sponsorblock-dom.cjs` |
| SB-10 | Local count/saved-time/per-category statistics; show toggle, reset; events deduplicated by session+sequence | `A/SponsorBlockStatistics.kt`, `A/SponsorBlockController.kt`, `A/SponsorBlockUi.kt` | `AT/SponsorBlockStatisticsTest.kt`, `AT/SponsorBlockControllerTest.kt` |
| SB-11 | Local bounded cache64 videos: positive6h, empty30min, failure5min; manual clear keeps backoff | `A/SponsorBlockClient.kt` | `AT/SponsorBlockClientTest.kt` |
| SB-12 | ≥1.1s requests, 429 Retry-After, network/server exponential1–60min backoff,5s timeouts,2MiB response cap,no redirects/cookies | `A/SponsorBlockClient.kt` | `AT/SponsorBlockClientTest.kt` |
| SB-13 | API failure leaves ordinary playback working; old video/opt-out callbacks discarded | `A/SponsorBlockController.kt` | `AT/SponsorBlockControllerTest.kt` |
| SB-14 | Attribution CC BY-NC-SA4.0, privacy disclosure (hash prefix not anonymity), no submissions/votes/view stats | `A/SponsorBlockUi.kt`, `THIRD-PARTY-NOTICES.md` | source behavior only |
| RYD-01 | Off-by-default consent for public video ID/IP exposure and estimated data | `A/PlayerSettings.kt`, `A/PlayerPreferences.kt` | `AT/PlayerPreferencesTest.kt` |
| RYD-02 | HTTPS votes GET, exact returned ID/deleted/type/range/integer validation; absence/error remains unknown, never invented zero | `A/ReturnDislikeRepository.kt` | `AT/ReturnDislikeRepositoryTest.kt` |
| RYD-03 | ≤1 request/1.1s and9500/day; success1h/error5min cache,max200;429 and Retry-After persists | `A/ReturnDislikeRepository.kt` | `AT/ReturnDislikeRepositoryTest.kt` |
| RYD-04 | Independent transport no OAuth/cookies/redirects;5s timeout,64KiB body; source generation/opt-out checks | `A/ReturnDislikeRepository.kt`, `A/PlayerController.kt` | RYD repository and player tests |
| RYD-05 | Count appended to existing recognizable dislike button, German grouped integer, estimate tooltip/accessibility; preserves click action | `A/ReturnDislikeScript.kt` | `S/check-advanced-player-dom.cjs` |

### Account, subscriptions, playlists, comments

| ID | Existing Android behavior | Android implementation | Android test evidence / qualification |
| --- | --- | --- | --- |
| ACC-01 | Optional official Google consent for `youtube.readonly`, separate from website login | `A/YoutubeAccountController.kt`, `A/AccountUi.kt` | `AT/AccountSessionGuardTest.kt`; actual Google configuration required |
| ACC-02 | Quiet restore of existing grant on explicit Account/Abos opening; no automatic consent on cold start | `A/YoutubeAccountController.kt` | session tests, historical `TESTING.md` |
| ACC-03 | New/different grant clears all old account lists, feed, pagination; session revision rejects old reads/writes | `A/AccountSessionGuard.kt`, `A/YoutubeAccountController.kt` | `AT/AccountSessionGuardTest.kt` |
| ACC-04 | Read-only grant remains usable after denied write permission; missing token/read permission clears prior account | `A/AccountSessionGuard.kt`, `A/YoutubeAccountController.kt` | `AT/AccountSessionGuardTest.kt` |
| ACC-05 | Revoke Google grant, clear local account metadata, preserve website session; failed revocation remains visible/retryable | `A/YoutubeAccountController.kt`, `A/AccountUi.kt` | session tests; do not conflate local sign-out and remote revocation |
| ACC-06 | Own channel title/avatar and all returned own channels; native links to their YouTube pages | `A/YoutubeAccountController.kt`, `A/AccountUi.kt` | `AT/PublicImageUrlPolicyTest.kt`; original channel data from API |
| ACC-07 | List subscriptions with pagination; separate real channel/subscription IDs | `A/YoutubeAccountController.kt`, `A/SubscriptionFeedData.kt` | `AT/SubscriptionFeedDataTest.kt` |
| ACC-08 | Chronological subscription upload feed,12-channel batches,3uploads/channel,4parallel upload calls,details batches50 | `A/SubscriptionFeedController.kt`, `A/SubscriptionFeedData.kt` | `AT/SubscriptionFeedDataTest.kt` |
| ACC-09 | Feed5min memory cache, manual refresh,load more channels,unavailable channels/status/empty handling | `A/SubscriptionFeedController.kt`, `A/SubscriptionsUi.kt` | `AT/FeedVisibilityLeasesTest.kt`, `AT/SubscriptionFeedDataTest.kt` |
| ACC-10 | Feed no background fetch when not visible; real requested videos/subscribed channels only; account changes empty cache | `A/SubscriptionFeedController.kt`, `A/FeedVisibilityLeases.kt` | `AT/SubscriptionFeedDataTest.kt`, `AT/FeedVisibilityLeasesTest.kt` |
| ACC-11 | Own playlists with pagination,select playlist, paginated available videos,refresh,back | `A/YoutubeAccountController.kt`, `A/AccountUi.kt` | account policy/fixture tests; private metadata does not unlock private web playback |
| ACC-12 | Authenticated video details/current rating/current subscription loaded for selected video; unknown state distinct | `A/VideoActionsController.kt`, `A/VideoActionsUi.kt` | `AT/VideoReadReloadGateTest.kt`, `AT/VideoActionPolicyTest.kt` |
| ACC-13 | Like/unlike via YouTube `videos/rate` after explicit interaction consent | `A/VideoActionsController.kt`, `A/VideoActionPolicy.kt` | `AT/VideoActionPolicyTest.kt`; no native separate dislike action |
| ACC-14 | Subscribe/unsubscribe with reread under current account before delete | `A/VideoActionsController.kt`, `A/YoutubeActionPayloads.kt` | `AT/YoutubeActionPayloadsTest.kt`, `AT/AccountSessionGuardTest.kt` |
| ACC-15 | Comment threads20/page/relevance/plaintext; disabled/forbidden/comment-consent status; replies50/page | `A/VideoActionsController.kt`, `A/VideoActionsUi.kt` | `AT/VideoReadReloadGateTest.kt`; write scope required by chosen authorized path |
| ACC-16 | Explicit comments permission button requests `youtube.force-ssl` but performs no write | `A/VideoActionsController.kt`, `A/YoutubeAccountController.kt` | `AT/VideoReadReloadGateTest.kt` |
| ACC-17 | Post comment/reply≤5000 chars,outer trim only,retain draft on failure,validate reply target/current grant | `A/VideoActionsController.kt`, `A/VideoActionsUi.kt`, `A/VideoActionPolicy.kt` | `AT/VideoActionPolicyTest.kt`, `AT/YoutubeActionPayloadsTest.kt` |
| ACC-18 | Server-created comment object rendered only after HTTP success; moderation may delay publication | `A/VideoActionsController.kt` | payload tests; real write E2E historically not accepted |
| ACC-19 | Save to existing own playlist; check duplicate first; reject WL/HL system playlists | `A/VideoActionsController.kt`, `A/VideoActionPolicy.kt` | `AT/VideoActionPolicyTest.kt`, `AT/YoutubeActionPayloadsTest.kt` |
| ACC-20 | GET may renew once on401; writes never replay automatically; ambiguous network write warns to verify state | `A/YoutubeAccountController.kt`, `A/VideoActionPolicy.kt`, `A/VideoActionsController.kt` | `AT/VideoActionPolicyTest.kt`, `AT/AccountSessionGuardTest.kt` |
| ACC-21 | Quota/disabled API/missing permission/network/consent errors visible without false success | `A/YoutubeAccountController.kt`, `A/VideoActionsController.kt` | policy tests and historical device checklist |
| ACC-22 | Public thumbnails only from ytimg/ggpht/googleusercontent HTTPS,3parallel,8MiB memory cache,2MiB body limit,bounded decode | `A/RemoteThumbnail.kt` | `AT/PublicImageUrlPolicyTest.kt` |

### History, external links, settings, updates, diagnostics

| ID | Existing Android behavior | Android implementation | Android test evidence / qualification |
| --- | --- | --- | --- |
| DATA-01 | Local history on by default;100max,canonical URLs,dedup,updated open time,title≤200 | `A/WeiktubeModel.kt` (`HistoryCodec`) | `AT/HistoryCodecTest.kt`, `AT/HistoryStoreTest.kt` |
| DATA-02 | Du carousel12 most recent with thumbnail/title/resume progress;All anzeigen;empty/paused notice | `A/RecentHistoryUi.kt`, `A/PersonalHomeUi.kt` (`HistoryPreview`) | `AT/RecentHistoryUiTest.kt` |
| DATA-03 | Full local history list with dates,resume time,playlist shortcut,delete confirmation | `A/WeiktubeUi.kt`, `A/RecentHistoryUi.kt` | `AT/RecentHistoryUiTest.kt` |
| DATA-04 | Late title metadata updates in place,does not reorder/recreate deleted records | `A/WeiktubeModel.kt` | `AT/HistoryCodecTest.kt`, `AT/HistoryStoreTest.kt` |
| DATA-05 | Resume normal YouTube video by ID;100max;persist after≥5s delta/force close;never save loading0/ad/invalid sample | `A/PlaybackProgressStore.kt`, `A/PlayerController.kt` | `AT/PlaybackProgressStoreTest.kt`, `AT/PlayerResumeSelectionTest.kt` |
| DATA-06 | Explicit timestamp including t=0 overrides stored progress;activity restore position outranks history | `A/Links.kt`, `A/PlayerController.kt` | `AT/PlaybackProgressStoreTest.kt`, `AT/PlayerResumeSelectionTest.kt` |
| DATA-07 | “An letzter Stelle fortgesetzt” + “Von vorne”; ended clears progress;history off prevents progress;clear history clears both | `A/PlayerController.kt`, `A/WeiktubeModel.kt`, `A/WeiktubeUi.kt` | `AT/PlayerResumeSelectionTest.kt`, `AT/HistoryStoreTest.kt` |
| DATA-08 | Settings and history persist app restarts/regular updates; tolerant malformed legacy items | `A/WeiktubeModel.kt`, `A/PlayerPreferences.kt` | `AT/HistoryCodecTest.kt`, `AT/PlayerPreferencesTest.kt` |
| DATA-09 | Clear cookies/cache/web storage with confirmation closes player;keeps local history and native OAuth independent | `A/MainActivity.kt`, `H/HomeEngine.kt`, `A/WeiktubeUi.kt` | historical device checklist; future stale clear callbacks important |
| LINK-01 | Accept YouTube HTTPS watch,short youtu.be,shorts,embed,live IDs on exact official hosts;strict11char ID | `A/Links.kt` | `AT/LinksTest.kt`, `AT/ExternalYoutubeIntentTest.kt` |
| LINK-02 | Parse t/start/#t numeric or h/m/s,cap86400;carry playlist/index without unrelated tracking values | `A/Links.kt` | `AT/LinksRegressionTest.kt`, `AT/ExternalYoutubeIntentTest.kt` |
| LINK-03 | External playlist,channel/@handle/user/c/channel subpages,search,feed routes;reject wrappers/malformed watch | `A/Links.kt` | `AT/ExternalYoutubeIntentTest.kt` |
| LINK-04 | Reject hostile schemes,credentials,ports,encoded slash/backslash/control/path traversal;external URL≤8192,share text≤16384 | `A/Links.kt`, `A/ExternalYoutubeIntent.kt` | `AT/ExternalYoutubeIntentTest.kt` |
| LINK-05 | Android ACTION_VIEW and plain-text ACTION_SEND extract first valid YouTube link;dedup restored launch/latest intent wins | `A/ExternalYoutubeIntent.kt`, `A/MainActivity.kt` | `AT/ExternalYoutubeIntentTest.kt`, `AT/YoutubeManifestTest.kt` |
| LINK-06 | Native manual open-link dialog accepts supported YouTube or allowed public HTTPS media | `A/WeiktubeUi.kt`, `A/Links.kt` | `AT/LinksTest.kt` |
| LINK-07 | Android default-link settings entry with fallback/explanation;no automatic foreign domain verification | `A/YoutubeLinkSettings.kt`, `A/WeiktubeUi.kt` | `AT/ExternalYoutubeIntentTest.kt`; iOS requires supported alternate UX |
| SET-01 | Theme System/Hell/Dunkel;logo/colors/nav retained | `A/WeiktubeModel.kt`, `A/WeiktubeUi.kt` | preference persistence tests |
| SET-02 | Player brightness/volume/doubletap/hold toggles,seek choice,hold rate,Wi-Fi/mobile quality,RYD | `A/PlayerSettings.kt`, `A/PlayerPreferences.kt` | `AT/PlayerPreferencesTest.kt` |
| SET-03 | Sponsor enabled,categories,markers,notices,statistics;cache/stat reset;privacy/attribution | `A/SponsorBlockUi.kt`, `A/SponsorBlockPreferences.kt` | SponsorBlock test sources |
| SET-04 | Adblock dedicated screen toggles/custom/exceptions/update/status/test/counters | `A/WeiktubeUi.kt` | filter tests |
| SET-05 | Local history save/clear,cookies/webdata clear,external links,installed version,terms/privacy/info | `A/WeiktubeUi.kt` | history/link tests |
| UPD-01 | Automatic app update check≤daily,manual check,current version/status/notes/new-version banner | `A/UpdateController.kt`, `A/UpdatePolicy.kt`, `A/UpdateUi.kt` | `AT/UpdatePolicyTest.kt` |
| UPD-02 | Custom HTTPS update feed;per-ABI APK selection;explicit download then install | `A/UpdateController.kt`, `A/UpdateManifest.kt` | `AT/UpdateManifestTest.kt` |
| UPD-03 | Download≤128MiB,feed≤64KiB;SHA256/package/version/certificate verify,normal Android installation approval | `A/UpdateController.kt`, `A/UpdatePolicy.kt` | `AT/UpdatePolicyTest.kt`; replace with iOS signing/TestFlight/store-distribution semantics |
| DIAG-01 | Fixed enums/codes for lifecycle,source generation,view attachment,renderer loss,pause reason,screen state | `A/PlayerDiagnostics.kt`, `A/MainActivity.kt` | `AT/PlayerDiagnosticsTest.kt`, `AT/MainActivityScreenStateTest.kt` |
| DIAG-02 | Bounded media event observer and pause-origin observation including mute/volume;unknown cause remains unknown | `A/PlayerPlaybackDiagnostics.kt`, `A/PlayerPlaybackObserver.kt` | `AT/PlayerPlaybackDiagnosticsTest.kt`, `S/check-playback-diagnostics.cjs`, `S/check-playback-observer.cjs` |
| DIAG-03 | No URLs/videoIDs/cookies/tokens/response bodies/raw stacks in app diagnostics | `A/PlayerDiagnostics.kt`, `A/PlayerPlaybackDiagnostics.kt`, `H/HomeConnectionDiagnostics.kt` | diagnostics tests |
| DIAG-04 | Home origin/routing/autofill status panel and error retry;legacy connection test screens isolated from current feed | `H/OriginalHomeController.kt`, `H/HomeConnectionActivity.kt`, `H/ChromeHomeTestActivity.kt` | `HT/HomeConnectionDiagnosticsTest.kt`, `HT/ChromeHandoffSelectionTest.kt` |

## Settings defaults and exact choices

| Persisted setting | Default | Choices / notes |
| --- | --- | --- |
| theme | `System` | System, Hell, Dunkel |
| shield | true | master blocker |
| ads | true | YouTube and base advertising domains |
| trackers | true | base trackers |
| domains / exceptions | empty | plain domain/hosts syntax, not ABP |
| saveHistory | true | also governs progress storage |
| playerBrightness | true | landscape gesture |
| playerVolume | true | landscape gesture |
| playerDoubleTap | true | landscape gesture |
| playerSeek | 10 | 5,10,15,20,30 seconds |
| playerHold | true | landscape gesture |
| playerHoldSpeed | 2.0 | candidate1.5,2,2.5,3; display only engine-reported capabilities |
| playerWifiQuality | 1080 | Auto(0),144,240,360,480,720,1080,1440,2160; engine capabilities constrain actual UI |
| playerMobileQuality | 720 | metered Wi-Fi also uses this setting |
| playerDislikes | false | confirmation and data explanation before enable |
| sponsorEnabled | false | confirmation before enable |
| sponsorMarkers | true | applies when enabled and valid timeline available |
| sponsorNotices | true | notice includes Undo; manual skip independent |
| sponsorStatistics | true | only shows/hides statistics; reset is separate |
| App automatic updates | true | `UpdateController.kt`;≤daily foreground check;source may be changed |

| SponsorBlock category | Label | Color | Default |
| --- | --- | --- | --- |
| sponsor | Sponsor | `#00d400` | Auto |
| selfpromo | Eigenwerbung | `#ffff00` | Auto |
| interaction | Like-/Abo-Aufruf | `#cc00ff` | Auto |
| intro | Intro | `#00ffff` | Manual |
| outro | Outro | `#0202ed` | Manual |
| preview | Vorschau/Rückblick | `#008fd6` | Off |
| music_offtopic | Musikfremder Abschnitt | `#ff9900` | Off |
| filler | Füllmaterial | `#7300ff` | Off |

`exclusive_access` is explicitly excluded as a whole-video label, not a skippable segment. No submission/voting features are implemented. Shorts SponsorBlock is not implemented in Android and should not be represented as existing parity.

## Stored data inventory

| Storage / source | Contents | Porting requirement |
| --- | --- | --- |
| DataStore `weiktube` / `A/WeiktubeModel.kt` | theme,shield/ads/trackers,custom/exceptions,history,all player/sponsor preferences | durable local typed settings with safe unknown-value defaults |
| SharedPreferences `video_progress` / `A/PlaybackProgressStore.kt` | normal YouTube ID→seconds,duration,updated;enabled;max100 | local resume independent of web sessions;clear revision prevents late resurrection |
| SharedPreferences `weiktube_account` / `A/YoutubeAccountController.kt` | linked and revocation_pending markers;access token only held in controller memory | Keychain for iOS OAuth tokens;separate local signout/remote revoke state |
| Memory account and feed stores | own channels,subscriptions,playlists,items,rating,comments,session revision;feed5min | clear all on account replacement;cancel/reject old work |
| Persistent Gecko profile | website cookies/storage/login;setup-presented marker and prior experiment proof | WKWebsiteDataStore.default;never copy/extract credentials or cookies |
| Android WebView cookie/storage | browser/watch/Shorts web state | persistent shared website store as permitted;no OAuth injection |
| SharedPreferences `sponsor_block_cache` | parsed segments,TTLs,backoff/failure counters | actor-safe bounded data cache,clear keeps rate limit |
| SharedPreferences `sponsor_block_statistics` | count,seconds,category counts | durable local ledger;undo/idempotency |
| SharedPreferences `ryd_cache` | counts/unknown,expires,backoff,next request,daily request budget | independent credentials-free transport and bounded persistence |
| Atomic file `weiktube-adblock/rules.signed.json` | verified update payload/signature | verify before install;atomic replacement;bundled fallback |
| SharedPreferences `weiktube_filter_updates` | last attempted daily update time | persisted rate limiting |
| Update controller preferences/cache | auto toggle,feed,last check,download APK/metadata | iOS update metadata/distribution route;no arbitrary self-install |
| Shorts sessionStorage | visit ID/user mute choice | preserve current explicit mute and no global permanent force-unmute |
| Public image memory cache |≤8MiB thumbnails | no account headers/cookies;bounded responses and decode |

## Bug history and the iOS invariants it implies

| Android reports | What was found / fixed | iOS invariant and test to preserve |
| --- | --- | --- |
| `RELEASE-1.3.5.md`, `ADBLOCK-1.3.5.md` | Domain filtering alone lacked YouTube ad coverage; added rule/scriptlet/cosmetic architecture | Test actual effects, signed-data validation, off/exceptions, and safe failure; never label compile success as ad-free |
| `RELEASE-1.3.6.md` | Old landscape safe-area/insets survived portrait return | Native host owns safe areas consistently; check both orientations with home indicator/cutout |
| `RELEASE-1.3.7.md` | Gecko extension background waited for first window while app waited for extension | Sequence initialization dependencies; for WK compile blockers before first network document with bounded error path |
| `RELEASE-1.3.8.md` | System PiP lifecycle/control integration | PiP user pause survives restore; no double player or premature background pause during valid transition |
| `RELEASE-1.3.9.md` | Tiny mobile viewport retained offsets and a360px closed drawer overlay; corrected geometry/hide narrowly | Retain logical layout during mini animation; inspect actual pixels and hit-test overlays, not only view bounds |
| `RELEASE-1.3.10.md` | Dead renderer touched by stale callbacks;fullscreen overlay ownership absent;Gecko dead session reference reused | Generation tokens,strict ownership,one bounded recovery;never call dead renderer;destroy callbacks safely |
| `RELEASE-1.3.11.md` | Actual YouTube pause from website handler at second small viewport; mini icon could disagree with action | Explicit play/pause semantics;do not fake background permission,visibility,or endless play retries |
| `RELEASE-1.3.12.md` | Old document callbacks polluted new selected video;empty media samples overwrote positions;confirmed blank document recovery added | Capture session/document generation at request and validate results;no timeout-based reloads |
| `RELEASE-1.3.13.md` | Stale screen-off flag after unlock/focus kept playback blocked | Reconcile real scene/activity state;resume view does not implicitly resume playback |
| `RELEASE-1.3.14.md`, `docs/HISTORY-PIP-AUDIO-REVIEW.md` | Stable viewport,explicit audible start,history carousel/title ordering/delete protections | Retain one player;respect mute/pause;do not recreate history from late metadata |
| `RELEASE-1.3.15.md`, `docs/SHORTS-RESUME.md`, `docs/SHORTS-ORIENTATION.md` | Shorts route retained;normal video positions;upside-down ignored | Typed route (watch versusShorts),timestamp precedence,orientation hysteresis |
| `RELEASE-1.3.16.md`, `RELEASE-1.3.18.md`, `docs/SHORTS-CONTROLS.md` | One early audio attempt marked success too soon/global player might be inactive/zero volume omitted;red bar lacked seek | Bind to active visible element+source+route;verify media state;explicit sound fallback;real one-time seek on release |
| `RELEASE-1.3.17.md`, `docs/VIDEO-ZOOM.md` | Pinch only media pixels,no full page scaling,no leftover-finger drag | Gesture arbitration and media-only transform;test multiple aspect ratios and reset routes |
| `RELEASE-1.3.19.md`, `docs/EXTERNAL-LINKS.md` | Strict external launch routing and restored launch dedup | Validate at extension/scheme/intent boundary;latest user link outranks old restored session |
| `RELEASE-1.3.20-rc1.md`, `RELEASE-1.3.20.md`, `docs/ADVANCED-PLAYER.md` | Gesture conflicts,temporary rate restoration,truthful quality capability,RYD consent/cache | Native gesture priority;restore baseline;test no false quality/RYD values |
| `RELEASE-1.3.21-rc1.md`, `RELEASE-1.3.21.md`, `docs/SPONSORBLOCK.md` | Optional community skip integration | Exact ID,duration,seeking proof;overlap merging,dedup,undo,no skip loops/no stale video |
| `RELEASE-1.3.22.md`, `docs/PLAYER-STABILITY.md` | First source animated from0 height;multiple animation clocks;fullscreen survived minimize/close | New selection begins at valid size;single transition state;fullscreen lifetime tied to player session |
| `RELEASE-1.3.23.md` | Mini began from whole watch-page rectangle,PiP source rect was wrong,website full-screen icon mismatched native landscape | Animate measured displayed video rectangle,retain source for PiP restore,one authoritative presentation state |

The repository contains 22 `RELEASE-*.md` reports (1.3.2;1.3.5–1.3.23 plus1.3.20-rc1/1.3.21-rc1). Older Home experiments and restoration reports remain in `ORIGINAL-HOME-TEST.md`, `HOME-CONNECTION-TEST.md`, `HOME-TAB-TEST.md`, `WEBSITE-FIRST-TEST.md`, `WEBSITE-LOGIN-TEST.md`, `GECKO-RETURN-TEST.md`, `PLAYER-HANDOFF-TEST.md`, `PLAYER-RETURN-TEST.md`, `RESTORATION.md`, `AUDIT.md`, and `TESTING.md`. Their rejected Chrome/native-home alternatives are historical context, not the current product UI. Current behavior is settled by the pinned production source, not an outdated test paragraph.

## Existing test inventory

App tests (all under `AT/`): AccountSessionGuardTest, AdvancedPlayerGestureTest, AdvancedPlayerIntegrationTest, ExternalYoutubeIntentTest, FeedVisibilityLeasesTest, HistoryCodecTest, HistoryStoreTest, HomeRoutePolicyTest, LinksRegressionTest, LinksTest, MainActivityScreenStateTest, NativePipControllerTest, PlaybackProgressStoreTest, PlayerComposeAttachmentTest, PlayerControllerLifecycleTest, PlayerDiagnosticsTest, PlayerDocumentLifecycleTest, PlayerDragGestureTest, PlayerModeContinuityTest, PlayerPlaybackDiagnosticsTest, PlayerPlaybackObserverTest, PlayerPreferencesTest, PlayerProgressTest, PlayerResumeSelectionTest, PlayerStableViewportTest, PlayerTransitionTest, PlayerVideoZoomGestureTest, PlayerViewportInsetsTest, PublicImageUrlPolicyTest, RecentHistoryUiTest, ReturnDislikeRepositoryTest, ShieldBaselineRegressionTest, ShieldEngineTest, SponsorBlockClientTest, SponsorBlockControllerTest, SponsorBlockStatisticsTest, SubscriptionFeedDataTest, UpdateManifestTest, UpdatePolicyTest, UprightVideoOrientationTest, VideoActionPolicyTest, VideoReadReloadGateTest, WatchNavigationPolicyTest, YoutubeActionPayloadsTest, YoutubeManifestTest (`.kt`).

Home tests (`HT/`): ChromeHandoffSelectionTest, HomeConnectionDiagnosticsTest, HomeContentRecoveryTest, HomeFeedDataTest, OriginalHomeApprovalTest, OriginalHomeAutofillPolicyTest, OriginalHomeBackgroundTest, OriginalHomeBridgeActivationTest, OriginalHomePolicyTest, OriginalHomeReturnPolicyTest, OriginalHomeTabBackgroundTest, WebsiteAccountSetupTest (`.kt`). Filter tests: `FT/FilterPackageTest.kt`.

JavaScript/browser tests (`S/`): `check-adblock-scripts.cjs`, `check-advanced-player-dom.cjs`, `check-advanced-player.cjs`, `check-browser-scripts.cjs`, `check-home-bridge.cjs`, `check-home-cold-start.mjs`, `check-native-pip-integration.cjs`, `check-original-home-navigation.cjs`, `check-playback-diagnostics.cjs`, `check-playback-observer.cjs`, `check-player-audio.cjs`, `check-player-layout.cjs`, `check-player-quality.cjs`, `check-player-scripts.cjs`, `check-shorts-audio.cjs`, `check-shorts-controls-layout.cjs`, `check-sponsorblock-dom.cjs`, `check-sponsorblock.cjs`, `check-video-zoom-layout.cjs`, `check-video-zoom.cjs`, `check-watch-navigation.cjs`, `test-gecko-adblock.mjs`. Preservation/integrity tools include `check-gecko-return-lifecycle.py`, `check-home-scope.py`, `vendor-adblock.mjs` and reviewed-change manifests. This audit did not run them.

## Licensing and attribution

- The authoritative project notice says **GPL-3.0-only** (`THIRD-PARTY-NOTICES.md`). `LICENSE` contains full GPLv3 text. Preserve this exact license in the iOS derivative and attribution to Weiktube contributors; mark the new iOS work and date as modifications.
- Selected **AdGuard Scriptlets2.5.1**, GPL3, copyright Adguard Software Ltd. and contributors. Four selected scriptlets and helpers, modified generator to silence logging and count real removals. If copying bundle/runtime, preserve `ADGUARD-LICENSE.txt`, `PROVENANCE.md`, exact corresponding source inputs/generator or reproducible source distribution. APK license notice is not enough by itself for copied iOS source.
- Bundled filter rule subset from AdGuard BaseFilter YouTube section under GPL3, reviewed2026-11-04. It intentionally does not cover every upstream workaround or server-inserted ads.
- **SponsorBlock data** attribution to sponsor.ajay.app under CC BY-NC-SA4.0, including noncommercial/share-alike terms for database-derived data. Android does not bundle SponsorBlock extension source and does not submit votes/segments.
- **Return YouTube Dislike** public read-only data integration; retain service attribution and links to its docs/usage rights. Android does not bundle its extension or voting code.
- Gecko/AndroidX/Kotlin/Google Play dependencies need not be copied into the native iOS app just to preserve behavior. Do not invent third-party notices claiming iOS bundles them if it does not. Their old notices can remain clearly identified as Android provenance.
- No private signing key is in the Android source. Public filter verification key and signature are provided. Do not invent replacement private key or falsely report signature verification success.

## Requested iOS work that is new or platform-specific, not an existing Android setting

- Share Extension, custom URL scheme, App Intents/Shortcuts are iOS equivalents/additions; Android has ACTION_SEND/VIEW and default link settings.
- Keychain OAuth token storage/ASWebAuthenticationSession/iOS OAuth client are platform adaptations; Google Play authorization cannot be copied.
- WKContentRuleList compilation and WKUserScript adaptations replace Android interception/Gecko extension mechanics; network-hit statistics may not be available through public WK APIs.
- AVPlayer for supported direct media and iOS system PiP are Apple-specific implementations. Android system PiP wraps the activity; Apple PiP cannot simply wrap arbitrary WebView pixels.
- Dynamic Type, VoiceOver, Reduce Motion, iPad split/window layouts and modern safe-area details require new iOS acceptance; Android references have semantic labels but no claim of comprehensive Apple accessibility.
- Native caption controls are not separately implemented in Android; captions are offered by the original website/native HTML controls.
- There is no dedicated Android setting for saved zoom, a manual Zoom-to-Fill switch, a separate miniplayer setting, download feature, offline video cache, cloud history sync, or SponsorBlock voting/submissions. These must not be falsely listed as existing Android functions.
- Android arbitrary APK self-update cannot be carried into iOS. Preserve installed version, release information, explicit user actions and source/distribution explanation using a supported signing/TestFlight/store/authorized alternative route.

## Suggested iOS acceptance priorities

1. Validate one persistent native playback owner with original website routes and supported HTML media control before claiming full player parity.
2. Test real watch→mini→watch and PiP transitions on an iPhone, including actual frame movement, aspect, audio, paused state, manual fullscreen exit and fast video changes.
3. Test real Shorts gesture/audio/element replacement behavior on device, with denied autoplay and intentional mute; fixtures alone cannot prove it.
4. Configure the real iOS OAuth client, consent screen/scopes/API enablement and test users; run read paths before write features, and never perform public account actions merely for test convenience.
5. Treat AdBlock rule compilation, JS fixture results, simulator builds, live YouTube observations and physical-device acceptance as distinct matrix evidence levels.
6. Preserve all pending statuses honestly. This source inventory contains actual Android features and platform equivalents; it does not certify any iOS implementation.

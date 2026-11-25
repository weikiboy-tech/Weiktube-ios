# Weiktube iOS

Native Swift-/SwiftUI-Umsetzung von **Weiktube Android 1.3.23** für **iOS und iPadOS 17+**. Die originale YouTube-Oberfläche bleibt in behaltenen WKWebViews; Navigation, Kontoansichten, Verlauf, Einstellungen, Playerergänzungen und Dienste sind native Module. Öffentliche direkte HTTPS-Videos verwenden einen separaten AVPlayer-Pfad.

**Stand: Quellcode vorhanden und Teilbereiche automatisiert geprüft; vollständiger iOS-Build und Geräteabnahme stehen aus.** Dies ist noch keine vollständig abgenommene Portierung und kein fertig signiertes Installationspaket. [FEATURE-PARITY.md](docs/FEATURE-PARITY.md) erfasst alle **163 vorhandenen Android-Funktions-IDs** sowie die iOS-Ergänzungen mit konkreten Dateien, Tests, Abweichungen und Status. Fehlende Funktionen werden dort ausdrücklich ausgewiesen.

## Was im Quellcode enthalten ist

- **Originale Startseite, Suche und Shorts:** Separate behaltene WKWebViews, strikt geprüfte YouTube-Routen, eigene Shorts-Timeline und Audioaktionen. Die ursprüngliche Tabfolge Startseite / Shorts / Adblock / Abos / Du und das mintfarbene Weiktube-Erscheinungsbild bleiben erhalten.
- **Player und native Darstellung:** Ein zentraler Präsentationszustand für Expandiert, Mini, Vollbild und PiP. Mini croppt/skaliert den bestehenden nativen Host um die tatsächliche Videofläche. Die App erzeugt für eine Präsentationsänderung keinen neuen YouTube-Player. Wiedergabeabsicht, Bildgeometrie und aktueller Audio-Besitzer sind getrennt.
- **Gesten und Steuerung:** Video-Pinch 1–8×, Doppeltipp mit gespeicherter Sprungweite, temporäres Tempo beim Halten, Helligkeit und öffentlicher Systemlautstärkeregler. Originale YouTube-Qualitäts-/Untertitelsteuerung bleibt erreichbar. AVPlayer nutzt öffentliche Präferenz-/Medienauswahl-APIs für erlaubte direkte Medien.
- **Konto und echte Data-API-Ansichten:** System-OAuth mit PKCE/State, Keychain, native Abos/Uploadfeed, Playlists, Bewertungen, Aboaktionen, Kommentare/Antworten und Speichern in eigene Playlists. Lese- und Interaktionsfreigabe sind separate Schritte. Eine Schreibfreigabe führt selbst keine Kontoaktion aus.
- **AdBlock:** Kompilierte WKContentRuleList, überprüfte lokale AdGuard-Scriptlets, kosmetische Regeln, eigene Domainlisten/Ausnahmen, signierte Datenupdates mit gepinntem Originalschlüssel, Status und tatsächliche Scriptlet-Zähler. Zusatzbrowser und lokale Shields-Testfläche sind enthalten.
- **SponsorBlock:** Standardmäßig aus, acht Kategorien mit Auto/Manuell/Aus, Hashpräfix-Abfrage, Dauer-/Identitätsprüfung, überlappende Segmente, bestätigte Seek-Zählung, Undo, lokale Statistiken und begrenzter Cache.
- **Return YouTube Dislike:** Standardmäßig aus, eigene Einwilligung, validierte geschätzte Werte, begrenzter Cache und Requestbudget. Fehler werden nicht als vermeintliche Null dargestellt.
- **Lokale Daten und iOS-Einstiege:** Begrenzter Verlauf/Resume, pausierte Auswahlwiederherstellung, öffentliche Releaseprüfung, atomische Persistenz, Share Extension mit App-Group-Inbox, Custom URL Scheme, App Intents/Kurzbefehle, Datenschutz-/Lizenzansicht und lokale Diagnose ohne Cookies/Tokens/URLs im Bericht.

Die Aufzählung beschreibt vorhandene Implementierung. Welche Teilfunktion vollständig geschrieben, nur teilweise vorhanden oder tatsächlich getestet ist, entscheidet die [Paritätsmatrix](docs/FEATURE-PARITY.md), nicht diese Übersicht.

## Nachweisstand

| Prüfung | Tatsächliches Ergebnis | Was damit nicht belegt ist |
| --- | --- | --- |
| SwiftPM, Swift 6.4.3 auf Linux | **41 XCTest-Fälle bestanden, 0 Fehler**: Router 9, Präsentationszustand 9, SharedLinkInbox 7, AtomicJSONFile 3, PlaybackRestoration 5, ReleaseMetadata 8 | App-/Extension-Target, SwiftUI, UIKit, AVFoundation, WebKit, Keychain und OAuth |
| `MediaBridgeTests.cjs`, Node 24.22.3 | **68 Verhaltensprüfungen bestanden** mit echter Bridge in VM-/DOM-/Medien-Fixture | Live-YouTube, echte WKWebView, Ton auf Hardware, Mini-Animation und System-PiP |
| `FilterRuntimeTests.cjs` | **Bestanden**: echte gebündelte Scriptlets/Runtime, sichere Gegenfälle, Originalsignatur/Manipulation | Effektive Werbefilterung in iOS oder auf Live-YouTube |
| `vendor-adblock.mjs --check` | **Bestanden**: gepinnte Quellinputs und reproduzierbares Bundle | Vollständiger App-Build oder aktuelle Website-Kompatibilität |
| Swift-Syntaxprüfung | Quellen geparst; kein Apple-SDK verwendet | Apple-API-Typprüfung, Verfügbarkeit, Linker, Signierung |
| Weitere XCTest-/UI-Testdateien | Geschrieben, nicht ausgeführt | Keine bestandenen Xcode-Tests behauptet |
| Xcode / Simulator / iPhone / iPad | **Nicht ausgeführt** | Keine Build-, Installations-, PiP-, OAuth- oder Geräteabnahme |

Testbefehle, Testumfang und noch nötige Abläufe: [TESTING.md](TESTING.md). Filterbelege: [ADBLOCK-VALIDATION.md](docs/ADBLOCK-VALIDATION.md). Das portable Package listet seine sechs tatsächlich kompilierten Produktionsdateien ausdrücklich in `Package.swift` auf.

## Lokal prüfen und mit Xcode fortsetzen

Die bereits ausgeführten plattformunabhängigen Prüfungen lassen sich aus dem Repository wiederholen:

```sh
swift test
node WeiktubeTests/MediaBridgeTests.cjs
node WeiktubeTests/FilterRuntimeTests.cjs
node Weiktube/AdBlock/VendorSource/vendor-adblock.mjs --check
python3 scripts/validate-project.py
```

Die JavaScript-Tests benötigen Node 22 oder neuer wegen der verwendeten VM-Funktion. Für die eigentliche iOS-App ist Xcode mit iOS-17+-SDK erforderlich. Das eingecheckte Projekt besitzt App-, Share-Extension-, Unit-Test- und UI-Testtargets. [BUILD.md](BUILD.md) beschreibt die genaue Projekt-/CI-Prüfung; [INSTALLATION.md](INSTALLATION.md) die reale Geräteinstallation und den möglichen späteren TestFlight-Weg.

In `Config/Local.example.xcconfig` stehen die Namen der benötigten Konfigurationen. Für Geräteinstallation müssen reale Apple-Team-/Bundle-/App-Group-Kennungen in der ignorierten lokalen Konfiguration gesetzt werden. Native Google-Anmeldung benötigt zusätzlich einen tatsächlich registrierten **iOS-OAuth-Client**, passende Redirect-URI/URL-Scheme und ein eingerichtetes Google-Cloud-Projekt. Kein Client-Secret, Token, Cookie, Zertifikat oder privater Schlüssel gehört ins Repository.

Ohne diese Konfiguration bleibt der Kontoeinstieg mit einer konkreten Erklärung nicht verfügbar. Eine fehlende App-OAuth-Konfiguration hat keinen Zusammenhang mit der bestehenden GitHub-Anmeldung dieser Arbeitsumgebung.

## Fachliche Grenzen

**Native Google-Freigabe und Website-Anmeldung sind getrennt.** Die Data API gibt den nativen Kontoansichten Zugriff. Sie meldet `m.youtube.com` in WKWebView nicht an und erzeugt keine personalisierten Originalempfehlungen. Die App kopiert weder Google-/Safari-Cookies noch native Tokens in die Website.

**YouTube entscheidet über seine Wiedergabefunktionen.** Originale Qualität, Untertitel, einbettbare Inhalte und WebKit-PiP hängen vom Video und der Website ab. Eine gespeicherte 1080p-Präferenz ist keine bestätigte YouTube-Qualitätsänderung. AVPlayer wird nur für ausdrücklich eingegebene zulässige öffentliche Direktmedien verwendet.

**AdBlock hat keine Zusage vollständiger Werbefreiheit.** Ein erfolgreich kompiliertes Regelwerk, die Anzahl seiner Regeln oder bestandene Node-Fixtures beweisen keine Wirkung auf reale YouTube-Werbung. Der lokale Shields-Test muss zuerst in WebKit ausgeführt werden und prüft synthetische Testregeln. Es werden keine Netzwerk-Blocktotalen erfunden.

**Die Veröffentlichung ist offen.** Kein signierter iPhone-Build, TestFlight-Upload oder App-Store-Review wurde durchgeführt. Apple-Signierung, App Group, echte OAuth-Registrierung und ein praktischer Medien-/UI-Test sind konkrete nächste Prüfschritte. Technisch umsetzbare noch fehlende Details stehen als „Noch nicht implementiert“ oder „In Entwicklung“ in [KNOWN-LIMITATIONS.md](docs/KNOWN-LIMITATIONS.md) und der Matrix.

## Android-Referenz und Herkunft

Referenzrepository: [weikiboy-tech/Weiktube](https://github.com/weikiboy-tech/Weiktube), Version **1.3.23**, versionCode **40**, Commit **`a7e0a9221e73d3d9c361f614adcb9e027fb70c35`**. Die Android-Quelle wurde als unveränderte Referenz behandelt. Ihre aktuellen Funktionen, Datenbestände, Testquellen, historischen Regressionen und exakten Defaults stehen in [ANDROID-REFERENCE.md](docs/ANDROID-REFERENCE.md).

Die neue iOS-Implementierung verwendet keine Android-/Gecko-Binaries. Wiederverwendete geprüfte Filterdaten/Scriptletquellen sind mit Lizenz, Originalversion, Quelle, vollständigen gepinnten Inputs und reproduzierbarem Generator dokumentiert.

## Repository- und Dokumentationsstand

Der iOS-Quellcode wird im öffentlichen Repository [weikiboy-tech/Weiktube-ios](https://github.com/weikiboy-tech/Weiktube-ios) auf dem Branch `main` entwickelt.

| Dokument | Zweck |
| --- | --- |
| [FEATURE-PARITY.md](docs/FEATURE-PARITY.md) | Alle 163 Android-IDs, iOS-Ergänzungen, Status, Dateien und Tests |
| [ANDROID-REFERENCE.md](docs/ANDROID-REFERENCE.md) | Gepinnte Originalquelle, vollständiger Audit, Defaults und Regressionen |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Medienbesitz, Zustände, WebKit/AVPlayer, Konto-/Datentrennung |
| [KNOWN-LIMITATIONS.md](docs/KNOWN-LIMITATIONS.md) | Fehlende Implementierung, unbestätigte Integration und echte Plattformgrenzen |
| [BUILD.md](BUILD.md) | Buildvoraussetzungen, Konfiguration und CI |
| [INSTALLATION.md](INSTALLATION.md) | Xcode-Geräteinstallation, Signierung, Share Extension und TestFlight |
| [TESTING.md](TESTING.md) | Tatsächliche Testprotokolle und noch offene Abnahme |
| [ADBLOCK-VALIDATION.md](docs/ADBLOCK-VALIDATION.md) | Filter-/Scriptlet-Tests und Grenzen des Nachweises |
| [PRIVACY.md](docs/PRIVACY.md) | Speicher-/Netzwerkflüsse und optionale Dienste |
| [REPOSITORY-STATUS.md](docs/REPOSITORY-STATUS.md) | Repository und Buildhistorie |
| [CHANGELOG.md](CHANGELOG.md) | Änderungen der iOS-Ausgabe |

## Lizenz

Das Projekt steht entsprechend der Android-Referenz unter **GPL-3.0-only**; siehe [LICENSE](LICENSE) und [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md). AdGuard Scriptlets 2.5.1 und die angepassten Filterteile behalten ihre Herkunfts-/GPL-Hinweise und zugehörigen Quellen. SponsorBlock-Communitydaten haben eine eigene CC-BY-NC-SA-4.0-Attribution; sie werden nicht mit der App-Quellcodelizenz gleichgesetzt. Return YouTube Dislike wird als optionaler öffentlicher Schätzdienst ausgewiesen.

# Prüfung und Abnahme von Weiktube iOS

Stand: **25. November 2026**. Dieser Stand enthält ausführbaren Produktionscode und tatsächlich ausgeführte portable Tests. **Ein vollständiger iOS-Build und eine praktische iPhone-/iPad-Abnahme sind noch offen.** Ein Linux-Test kann weder Apple-Frameworks typprüfen noch echte YouTube-Wiedergabe nachweisen.

## Tatsächlich ausgeführte Prüfungen

| Prüfung | Ergebnis | Geltungsbereich |
| --- | --- | --- |
| Foundation-XCTest mit Swift 6.4.3 auf Linux | **41 Tests, 0 Fehler** | Sechs ausdrücklich ausgewählte Produktionsdateien in `Package.swift` |
| Linkrouter | **9 bestanden** | Gültige Hosts/Formate, Zeitstempel einschließlich 0, Playlists, Wrapper, bösartige/mehrdeutige URLs, zulässige Direktmedien |
| Präsentationszustand | **9 bestanden** | Mini/Expandiert/Vollbild/PiP, manuelles Verlassen, ignorierte Kopfüber-Lage, Quellenwechsel und Zoomgrenzen |
| Gemeinsame Link-Inbox | **7 bestanden** | App-/Extension-Konkurrenz, Bestätigung bekannter Elemente, zwischenzeitliche neue Zustellungen, Grenzen, Ablauf und Neustart |
| Atomische JSON-Dateien | **3 bestanden** | Austausch, Neustart, Größengrenzen; ungültiges neues Schreiben zerstört gute Daten nicht |
| Wiederherstellungsspeicher | **5 bestanden** | Getrennte Route/Position, deaktivierter Verlauf, zulässige Auswahl, Alter, periodische/erzwungene Speicherung |
| Release-Metadaten | **8 bestanden** | Versionsreihenfolge, Vorabversionen, echte Release-/Asset-URL-Zuordnung einschließlich kanonischer Repository-Schreibweise, ungültige/überlange Eingaben |
| JavaScript-Medienbridge | **68 Verhaltensprüfungen bestanden**; Assertions im [Protokoll](docs/validation/media-bridge-tests.txt) | Das echte gebündelte Script in kontrollierten DOM-/Medien-Fixtures; keine Browser- oder Geräteemulation |
| Filter-Runtime und Vendor-Herkunft | **Bestanden** | Reale gebündelte Scriptlets, JSON/fetch/XHR-Pruning, sichere Gegenfälle, Originalsignatur und Manipulation, reproduzierbares Bundle |
| Xcode-Projektgenerator und Strukturvalidator | **Bestanden**; [Protokoll](docs/validation/project-validation.txt) | Quellen-/Ressourcenmitgliedschaft, vier Targets, Extension-Einbettung, Konfiguration, Scheme und sichere abgeleitete Info.plist |
| Swift-Syntaxparse | **69 von 69 Dateien bestanden**, 0 Fehler; [Parse-Protokoll](docs/validation/swift-parse-results.json) | Syntaxprüfung; ausdrücklich kein Apple-SDK-Typecheck |

Die vollständigen XCTest-Meldungen stehen in [swift-tests.txt](docs/validation/swift-tests.txt). [swift-test-results.json](docs/validation/swift-test-results.json) ist eine aus diesem echten Textprotokoll abgeleitete Zusammenfassung, kein erfundenes Xcode-Ergebnis. Die tatsächlich geprüften Quelldateien und SHA-256-Werte stehen in [source-hashes.json](docs/validation/source-hashes.json). [swift-version.txt](docs/validation/swift-version.txt) und [swift-signature.txt](docs/validation/swift-signature.txt) dokumentieren den verwendeten offiziellen Compiler. Compiler-Download, Signaturprüfung und ausgeführte Befehle sind in [swift-qa-summary.json](docs/validation/swift-qa-summary.json) festgehalten.

SwiftPM hat im ausgeführten Lauf trotz angefordertem `--xunit-output` keine XML-Datei erzeugt. Deshalb wird keine solche Datei als Testbeleg ausgegeben. Das Textprotokoll ist der maßgebliche Nachweis.

## Geschrieben, aber hier nicht ausgeführt

Die XCTest-Dateien für `AppSettings`, `HistoryStore`, Account-/PKCE-/Payloadregeln, SponsorBlock, RYD, ReleaseChecker sowie die Security-/WKContentRuleList-Prüfung sind im Xcode-Testtarget enthalten. Die drei UI-Tests prüfen native Tabnavigation, die Suchmaske und die Ablehnung eines gefährlichen Links im Offline-Testmodus. Diese Quellen sind **kein behaupteter Testpass**.

Auch die Produktionsintegration zwischen Wiederherstellungsspeicher, App-Lifecycle, tatsächlicher Mediendatei und Audio-Besitz ist noch nicht durch einen App-Test belegt. Die 41 portablen Tests prüfen die angegebenen Core-Komponenten, nicht `PlayerCoordinator` oder `AppModel`.

Folgende Ergebnisse liegen nicht vor:

- macOS-/Xcode-Kompilierung, Linkerprüfung, Simulatorstart oder Simulator-XCTest/XCUITest;
- signierte Installation auf iPhone/iPad, gestartete Share Extension oder bestätigter App Intent;
- Live-YouTube-Wiedergabe, hörbare Shorts, echtes PiP, Rotation oder visuelle Animationsprüfung;
- echte Google-Systemanmeldung, Zugriff auf private Kontodaten oder ausgeführte Konto-Schreibaktionen;
- reale WebKit-AdBlock-Wirkung, längere Wiedergabe, Speicher-/Energie-/Frame-Messungen;
- IPA, TestFlight-Upload, App-Store-Abnahme oder erfolgreich gelaufene GitHub Actions.

Die Arbeitsumgebung hat keinen macOS-Runner mit Xcode. Die macOS-CI ist vorbereitet. Das inzwischen vorhandene leere Zielrepository ist öffentlich; der ausdrücklich privat gewünschte Entwicklungsstand wurde dort noch nicht hochgeladen. Daher wurde kein CI-Lauf gestartet. Details stehen in [REPOSITORY-STATUS.md](docs/REPOSITORY-STATUS.md).

## Reproduzierbare lokale Prüfungen

Vom Projektverzeichnis aus:

```sh
swift test
node WeiktubeTests/MediaBridgeTests.cjs
node WeiktubeTests/FilterRuntimeTests.cjs
node Weiktube/AdBlock/VendorSource/vendor-adblock.mjs --check
python3 scripts/generate-project.py --check
python3 scripts/validate-project.py
```

Der portable Testlauf verwendet Swift 5 als Sprachmodus; der tatsächlich ausgeführte Compiler war Swift 6.4.3. Node 22 oder neuer ist für die JavaScript-Fixtures vorgesehen. Die Vendor-Prüfung lädt bei `--check` keine beliebige neue Scriptletversion nach. Die zugehörigen ursprünglichen Eingaben bleiben gepinnt.

Für den echten App-Build gelten die Befehle in [BUILD.md](BUILD.md). Die CI entdeckt einen installierten iPhone-Simulator, führt `xcodebuild build test` und `analyze` aus und erhält Logs/`.xcresult` auch bei Fehlern. Ein möglicherweise erzeugtes Simulator-`.app`-Archiv ist getrennt vom Testausgang zu bewerten.

## Praktischer Abnahmeplan

Jeder Durchlauf muss den getesteten Git-Commit, Xcode-/SDK-Version, iOS-/iPadOS-Version, Gerätemodell, Netz, Einstellungen und Beobachtung enthalten. Als Ergebnis sind „Bestanden“, „Fehlgeschlagen“ oder „Nicht durchgeführt“ einzutragen. Der folgende Plan ist **nicht ausgeführt**.

| Bereich | Konkrete Durchführung | Zu beobachtendes Ergebnis |
| --- | --- | --- |
| Kaltstart / Wiederherstellung | Video auswählen, Position erreichen, pausieren, App beenden, neu öffnen; danach mit anderem externen Link starten | Letzte Auswahl erscheint minimiert und pausiert; expliziter neuer Link gewinnt; keine fremde Audio-App wird durch bloße Wiederherstellung unterbrochen |
| Verlaufslöschung | Während aktiver Wiedergabe Verlauf löschen/deaktivieren, weiter abspielen, schließen, neu starten | Alte Rückmeldungen erzeugen weder Verlauf noch Wiederherstellung neu |
| Lange Wiedergabe | Mindestens eine Stunde mit Netzwerkwechsel, Pause, Hintergrund und Vordergrund | Kein zweiter Audiobesitzer, keine unbeschränkte Task-/Listener-/Speicherzunahme; Abbrüche mit tatsächlicher Ursache dokumentieren |
| Schneller Quellenwechsel | A→B→C während Metadaten, Resume, SponsorBlock und RYD noch laufen; wiederholt | Keine alte Position, Dislikezahl, Werbe-Recovery oder Sponsor-Zählung wird auf die neue Auswahl übertragen |
| Vollbild / Rotation | Hochformat, beide Querformate, manuell Vollbild verlassen, unveränderte Haltung, Kopfüber | Symbol entspricht Zustand; manuelles Verlassen rastet bis echter Lageänderung ein; kein sofortiges Wiedereintreten |
| Mini / Animationen | Wiederholt ziehen, langsames Abbrechen, schneller Fling, Tabnavigation, Vergrößern, Pausieren, Schließen | Dieselbe Wiedergabeinstanz, korrekte Geometrie, kein Schwarzbild/Audiosprung; nicht nur Endzustände aufnehmen |
| Pinch / Gesten | Unterschiedliche Seitenverhältnisse, Fokus am Rand, zweimaliges Pinch, anschließender Einfingerkontakt, Originalcontrols | Nur Video wird skaliert; keine sprungartigen Folgegesten oder verschobenen Websitecontrols |
| Zeit-/Tempo-/Lichtaktionen | Wiederholte Doppeltipps beiderseits, Long-Press und Fingerabbruch, Helligkeitsänderung, Menü/Minimierung | Kumulierte Ziele stimmen; vorheriges Tempo und ursprüngliche Helligkeit werden wiederhergestellt; Lautstärke erfolgt über öffentlichen Systemregler |
| PiP | Unterstützte Webvideos und öffentliches Direktvideo, System-PiP, Hintergrund, Rückkehr, Schließen; auch nicht unterstützter Inhalt | Nur bestätigter System-PiP-Zustand ändert den Reducer; keine zweite Quelle oder gefälschte erfolgreiche PiP-Anzeige |
| Shorts | Schnelle vertikale Wechsel, Nutzermute, Tippen/Drag auf Timeline, Wechsel während Seek, Unterbrechung und Rückkehr | Ein hörbares Element; absichtliches Mute bleibt bestehen; alter Seek trifft kein neues Short; Autoplay-Verweigerung zeigt echte Nutzeraktion |
| Filter | Lokaler Shields-Test, danach reale Home/Watch/Shorts-Seiten; Filter aus/ein, Ausnahmen, ungültiges Update | Kontrolle und blockierte Ressource im lokalen Test unterscheidbar; echte Werbung anhand Beobachtung protokolliert; letzte gute Regeln bleiben bei Fehler aktiv |
| SponsorBlock / RYD | Opt-in/Opt-out während Request, API offline/429, falsche Video-ID/Dauer, überlappende Segmente, manueller Skip/Undo | Kein Seek bei falscher Identität/Live/Ad, keine doppelte Statistik, keine erfundene Null; native und DOM-Anzeige entfernen sich bei Opt-out |
| Konto | Tatsächlich registrierter iOS-Client, Consent-Abbruch, Read-Grant, Write-Upgrade, Kontowechsel, Tokenablauf, Widerruf | Kein Passwort im App-WebView, keine Cookieübertragung, kein veraltetes Kontoergebnis; jede Schreibaktion verlangt echte Nutzerabsicht |
| Links / Extension | Alle Router-Testformate über tatsächliches Teilen, App Intent und URL Scheme; parallele Zustellung | Sichere Inbox, keine verlorene neue Zustellung, kein erzwungener privater Hoststart |
| WebKit / Lifecycle | Tatsächlichen Prozessverlust im Debugbuild auslösen, langsame und leere Seiten unterscheiden, wiederholten Abbruch provozieren | Begrenzte Recovery; gespeicherte Position/Play-Absicht; keine Reload-Schleife oder Timeout-Neuladung einer nur langsamen Seite |
| iPad / Accessibility | Split View, Stage Manager, Hoch-/Querformat, große Schrift, VoiceOver, Reduce Motion, Hardwaretastatur | Erreichbare Controls, sichere Ränder und Fokusfolge; alternative Bedienung der Gesten; keine abgeschnittenen zwingenden Aktionen |

Konto-Schreibtests sollen an einem ausdrücklich dafür vorgesehenen Testkonto und anhand einer konkreten Testaktion ausgeführt werden. Die aktuelle Entwicklung hat keine Bewertung, kein Abo und keinen Kommentar im Nutzerkonto vorgenommen.

## Performance-Evidenz

Auf Hardware sind Instruments Allocations/Leaks, Time Profiler, Animation Hitches und Energy Log sinnvoll. Festhalten: Start bis bedienbare Oberfläche, Auswahl bis erstes Bild, Speicher vor/nach identischen Quellen-/Tabwechseln, Hitches während der sichtbaren Mini-/Vollbildbewegung, CPU-/Netzwerkaktivität bei Pause und Hintergrund. Immer denselben Inhalt, dieselbe Netzbedingung und denselben Gerätestand vergleichen.

Es gibt in diesem Repository **keine gemessenen FPS-, RAM-, Akku- oder Startzeitwerte**. Solche Werte dürfen erst nach der beschriebenen Messung ergänzt werden. Das Architekturziel „langlebige Views, keine aggressive Polling-Schleife, begrenzte Caches“ ersetzt diese Messung nicht.

## Freigabe

Die [Paritätsmatrix](docs/FEATURE-PARITY.md) bleibt verbindlich. Eine Zeile wird erst nach dem entsprechenden echten Nachweis zu „Im Simulator getestet“ oder „Auf echtem Gerät bestätigt“. Vor einer Nutzer-Testversion müssen der vollständige App-/Extension-Build, die notwendigen Signierungs-/OAuth-Konfigurationen, die wesentlichen Medien-/Konto-/Filterflüsse und die dokumentierten offenen Implementierungen geprüft sein. Der aktuelle Source-Stand ist keine behauptete Erfüllung dieser Freigabe.

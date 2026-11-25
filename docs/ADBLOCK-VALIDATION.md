# AdBlock-, SponsorBlock-, Dislike- und Medienbridge-Prüfung

Stand: 25.11.2026. Android-Referenz: Weiktube **1.3.23**, Commit
`a7e0a9221e73d3d9c361f614adcb9e027fb70c35`.

## Prüfung mit WebKit im Simulator

Der Test `testLocalFilterScreenActuallyBlocksItsImageAndHidesItsAd` öffnet die lokale Shields-Testseite der App. WKWebView lädt das Kontrollbild, blockiert das zweite Bild und blendet das Testelement per kosmetischer Regel aus. Der Test bestand auf dem iPhone SE und dem iPad mini mit Systemversion 26.2. [Xcode-Protokoll](https://github.com/weikiboy-tech/Weiktube-ios/actions/runs/45614957738/job/139217642069)

## Frühere plattformunabhängige Prüfungen

Die unten als bestanden bezeichneten Prüfungen wurden tatsächlich mit Node.js in
der Linux-Entwicklungsumgebung ausgeführt. Sie führen den ausgelieferten
JavaScript-Code aus. Ein lokales DOM-/Medienmodell ersetzt dabei Browser,
Videodecoder und Netzwerk. Die Ergebnisse belegen die genannten Codepfade,
**keine tatsächliche Werbefreiheit oder funktionierende YouTube-Wiedergabe auf
iPhone/iPad**.

## Tatsächliche Ergebnisse

Alle Befehle werden im Repository-Verzeichnis ausgeführt.

| Befehl | Beobachtetes Ergebnis |
| --- | --- |
| `node WeiktubeTests/FilterRuntimeTests.cjs` | Bestanden. Originale gebündelte Scriptlets und iOS-Runtime wurden ausgeführt; die unten aufgeführten Filter- und Sicherheitsfälle bestanden. |
| `node WeiktubeTests/MediaBridgeTests.cjs` | Bestanden: **68 Verhaltensprüfungen** der tatsächlichen Medienbridge. |
| `node Weiktube/AdBlock/VendorSource/vendor-adblock.mjs --check` | Bestanden: SHA-256 der drei gepinnten Upstream-Eingaben und bytegenau reproduzierbarer Scriptlet-Output. |
| `node --check Weiktube/Resources/MediaBridge.js` | Bestanden: JavaScript-Syntax. |
| `node --check Weiktube/Resources/Filters/filter-runtime-ios.js` | Bestanden: JavaScript-Syntax. |
| Vergleich des signierten Request-Matchers mit der Swift-Schema-Konstante | Zeichengetreu identisch. |

`FilterRuntimeTests.cjs` benötigt Node.js 22 oder neuer, da es echte
Eigenschaftsdeskriptoren über `vm.constants.DONT_CONTEXTIFY` prüft. Der Generator
benötigt kein Herunterladen oder Installieren von Paketen.

Der abschließende Lauf verwendete **Node 24.22.3**. Die tatsächlichen Befehle,
Exitcodes und SHA-256 der geprüften Quelldateien liegen in
[media-bridge-tests.txt](validation/media-bridge-tests.txt) und
[filter-runtime-tests.txt](validation/filter-runtime-tests.txt). Diese Protokolle
enthalten keine Kontodaten oder Netzwerkantworten.

### Filterfälle

Der Test prüft die RSA-SHA-256-Signatur der tatsächlich gebündelten `rules.json`
mit dem tatsächlich gebündelten öffentlichen Schlüssel. Veränderte Nutzdaten
können die bestehende Signatur nicht wiederverwenden. Die Vendor-Eingaben werden
gegen die aus Android übernommenen, festen SHA-256-Werte geprüft.

Die tatsächlich generierten Scriptlets entfernen die vorgesehenen Werbefelder
aus Initialdaten sowie JSON-, Fetch- und XHR-Antworten. Metadaten, Streaming- und
Untertitelstrukturen bleiben in den Fixtures erhalten; unveränderte Antworten
erhöhen die Entfernungszähler nicht. Fetch-/XHR-Metadaten und vorhandene
Request-Parameter bleiben erhalten. DRM-, fremde API- und CDN-Pfade werden durch
die begrenzten Response-Matcher nicht erfasst.

Zehn modellierte SPA-/Werbewechsel prüfen, dass derselbe Werberenderer nur einmal
gezählt, sichtbare Werbung pausiert und stummgeschaltet, eine ausgeblendete
Werbe-UI-Vorlage hingegen nicht als laufende Werbung behandelt wird. Die Runtime
ruft weder `play()` noch einen Seek auf. Vorher bewusst pausierte Videos werden
nicht gestartet. Das Wiederherstellen des vorherigen Mute-/Sichtbarkeitszustands,
idempotente Installation und begrenzte Ereignisdaten ohne Response-/Auth-Logs
werden geprüft.

Ausnahmen, Deaktivierung, Authentifizierungspfade einschließlich kodiertem
`/%73ignin`, falsche Ursprünge, nicht erlaubte Ports, fehlende Konfiguration und
nicht unterstützte Hooks haben eigene Fälle. Validierte YouTube-Embed-Frames
und `youtube-nocookie.com` werden durch die iOS-Anpassung zugelassen. Der
nativen WebKit-Bridge obliegen zusätzlich Ursprung-, Token-, Versions- und
Größenprüfung; deren Swift-Ausführung benötigt die Apple-Testumgebung.

### Medienbridge-Fälle

Die 68 Verhaltensprüfungen decken ab:

- Auswahl des sichtbaren Shorts-Videos und Pausieren anderer Videoelemente;
- genau einen hörbaren Eigentümer, native Suspendierung und verhinderten
  Neustart durch Seitenskripte während inaktiver Ansicht;
- Erhalt bewusster Stummschaltung beim nächsten Short sowie Wiederaufnahme nur
  eines zuvor laufenden Shorts nach Rückkehr;
- Erhalt einer bewussten Pause nach Tab-Wechsel;
- Ablehnung veralteter Videoelemente und veralteter SPA-Identität noch vor dem
  nächsten Animationsframe;
- zusätzliche opake Quellrevision bei `currentSrc`-Wechsel im gleichen DOM-Knoten,
  Abbruch laufender alter Seeks, keine Weitergabe der Medien-URL und kein
  unnötiges Pausieren/Neustarten bei adaptivem Quellenwechsel;
- Seek-Erfolg erst nach passendem `seeked`, Positionsabweichung höchstens
  0,35 Sekunden, Ablehnung falscher Positionen, Timeout und alter Kontextantworten;
- Ablehnung alter Generation auch bei versehentlich gleichem Token; reale
  Seek-Ranges mit Lücken, Randbegrenzung vor dem exakten Videoende und Ablehnung
  unbekannter/unendlicher Dauer;
- Vergrößerung ausschließlich des Videoelements, Wiederherstellung eigener
  Zoom-/Clipping-Änderungen und unveränderte Skalierung von Bedienelementen;
- Fokalpunkt, Begrenzung auf 1–8×, unzulässige/nicht endliche Ankerwerte und
  Wiederherstellung vorheriger Transform-/Origin-Werte;
- normalisierte sichtbare DOM-Control-Rechtecke, begrenzte Anzahl und sichere
  Medien-Diagnosefelder ohne rohe Fehlerantwort;
- Hold-Geschwindigkeit, Loslassen außerhalb des sichtbaren Videos und
  Wiederherstellung bei Kontextwechsel bzw. doppelter Bridge-Aktivierung;
- zehn Layout-Wechsel mit vollständiger Wiederherstellung ursprünglicher
  Inline-Styles, auch bei mehrfach bearbeiteten Vorfahren;
- Weitergabe einer echten Vollbildinteraktion an die native Zustandsverwaltung,
  ohne Annahme erfolgreicher Systemrotation;
- Wiederanschluss des MutationObservers nach einer Back-forward-cache-Rückkehr;
- keine automatische Wiedergabe versteckter Shorts, ehrlicher Autoplay-Fehler
  und keine aggressive Wiederholung;
- erster Startversuch erst nach Bereitschaft, `loadeddata`/`canplay`-Aktualisierung
  und Verwerfen alter Play-Promise-Ablehnung nach Quellenwechsel;
- RYD-Dekoration am erkannten Originalbutton mit exakt einer Textmarkierung,
  Schätzungsattribution, erhaltenem Klick/Originalinhalt, keinem HTML-Parsing,
  richtiger Video-ID, Opt-out, SPA-Bereinigung und Längenlimit;
- abgewiesene Werbe-Seeks, fremde Ursprünge, HTTP, Anmeldedaten in URLs,
  unerlaubte Ports und Unterframes sowie sichere/unsichere Navigationsanker.

Diese Tests haben konkrete Fehler gefunden, die im ausgeführten Quellstand
korrigiert wurden: eine alte SPA-ID konnte zuvor bis zum nächsten Frame gültig
erscheinen; doppelte Aktivierung konnte den vorherigen Hold-Wert verlieren;
Layout-Rücknahme in vorwärts gerichteter Reihenfolge ließ bei mehrfach
bearbeiteten Knoten Zwischenstyles zurück; der DOM-Observer wurde nach
Back-forward-cache-Rückkehr nicht erneut registriert. Die ergänzten Prüfungen
fanden zusätzlich die fehlende Quellrevision bei demselben DOM-Element, den
verlorenen Hold-Wert beim gleichen Element mit neuer Route und einen zu früh
verbrauchten Shorts-Startversuch vor Medienbereitschaft. Alte Play-Promises und
Seek-Generationen werden nun getrennt vom aktuellen Medium geprüft. Ein Seek
auf eine Range-Grenze wird in den spielbaren Bereich zurückgenommen.

## Vorbereitete Apple-Tests

`SponsorBlockTests.swift`, `ReturnDislikeTests.swift` und `AdBlockTests.swift`
enthalten zusammen 14 XCTest-Fälle. Sie prüfen Hash-Präfix und ID-Abgleich,
ungültige Daten, überlappende Segmente, Seek-Bestätigung, Undo, fehlende bzw.
abweichende Videodauer, alte Generationen, bewusste Seeks, Live-/Werbe-/Pause-Gates,
Dislike-Zahlen und Rate-Limit-Header, Domainvalidierung, Signatur/Tamper/Rollback
und echte Kompilierung der JSON-Regeln durch `WKContentRuleListStore`.

Der vorhandene SponsorBlock-Regressionsfall prüft außerdem die Trennung von
Seekabsicht und bestätigter Landeposition: Ein begonnener/fehlgeschlagener
Nutzer-Seek darf eine bereits gezählte Überspringung nicht zurückbuchen;
bestätigtes Zurückspulen in das Segment kann sie genau einmal zurückbuchen.
Die Anzahl der XCTest-Fälle bleibt unverändert, da diese Regression denselben
vorhandenen Testfall erweitert. Der native Coordinator wartet entsprechend auf
die Medienbestätigung und verwirft alte Dokument-/Quell-/Elementantworten.

**Diese 14 XCTest-Fälle wurden hier nicht ausgeführt.** Auch der dafür vorbereitete
WebKit-Kompilierungstest ist noch kein bestandenes Ergebnis. Swift-Parserprüfung
oder andere Core-Tests, soweit separat ausgeführt, ersetzen diese Tests nicht.

## Offen für Simulator und echte Geräte

Die folgenden Prüfungen sind noch erforderlich und dürfen nicht aus den
Node-Ergebnissen abgeleitet werden:

| Prüfung | Benötigte Evidenz |
| --- | --- |
| WKContentRuleList auf iOS 17 und aktuellen Systemen | Erfolgreiche Kompilierung, tatsächliche Anfrageunterdrückung und erhaltene Medien-/Untertitel-/Anmeldepfade. |
| Echte YouTube-Werbeauslieferung | Preroll, Midroll, Shorts und Home mit dokumentierten Testbedingungen; keine Garantie gegen jede Werbevariante. |
| SponsorBlock-Netzwerk und Mediengrenzen | Erfolgreicher Hash-Bucket-Abruf, genaue Zeitgrenzen, manuelle/automatische Sprünge, Undo, App-Hintergrund und PiP. |
| Dislike-Anzeige | Aktuelle echte Antwort, richtige Videozuordnung, Cache, 429/Offline, klar erkennbare Schätzungskennzeichnung. |
| Filterupdates | iOS-Download, Redirect-Policy, Signatur, beschädigter/älterer Kandidat und Beibehaltung des letzten gültigen Regelsatzes. |
| Wiedergabe und Lifecycle | Schnelle Wechsel, Rotation, Audioeigentümer, Prozessabbruch, Rückkehr nach Inaktivität und längere Sessions. |
| Animationen | Sichtbare Bewegung auf iPhone/iPad einschließlich Miniplayer-Cropping; keine Endzustandsprüfung als Ersatz. |

## Bewusste technische Grenzen

`WKContentRuleList` liefert keine öffentlichen Trefferzähler je Anfrage. Die App
zeigt daher die Anzahl kompilierter Regeln und getrennt benannte
seitenbeobachtete Änderungen. Sie erfindet keine Zahl blockierter
Netzwerkanfragen.

Installierte Scriptlet-Property-Traps lassen sich in einem laufenden Dokument
nicht zuverlässig entfernen. Nach einer Filteränderung informiert die Oberfläche
deshalb über den notwendigen, ausdrücklich ausgelösten Seiten-Reload. Die
Wiedergabe wird für ein routinemäßiges Filterupdate nicht heimlich neu erstellt.

Erkannte durchgebrochene Werbung wird pausiert und abgedeckt. Der native
Coordinator hat einen begrenzten geschützten Recovery-Reload je Quelle und
danach eine ausdrückliche Fehlermeldung. Dieser Swift-Integrationspfad ist
geschrieben, nicht ausgeführt. Ein Retry bzw. eine ausdrücklich gewählte
Filteränderung kann weiterhin nötig sein; die appweite Zuverlässigkeit dieses
Ablaufs bleibt Gegenstand der Geräteabnahme.

Die SponsorBlock- und RYD-Transporte teilen keinen Browser-Cookiespeicher und
keine Google-Authorization. Hash-Präfix-Abfragen sind keine Anonymitätsgarantie:
SponsorBlock erhält Präfix und Verbindungsmetadaten; RYD erhält die öffentliche
Video-ID und Verbindungsmetadaten. Die Funktionen sind standardmäßig aus.

## Quellen

- [Android-Filterprovenienz](https://github.com/weikiboy-tech/Weiktube/blob/a7e0a9221e73d3d9c361f614adcb9e027fb70c35/content-filter/src/main/assets/weiktube-adblock/PROVENANCE.md)
- [Vorhandener signierter Filterrelease](https://github.com/weikiboy-tech/Weiktube/releases/tag/adblock-rules-v1)
- [AdGuard Scriptlets 2.5.1](https://github.com/AdguardTeam/Scriptlets/tree/v2.5.1)
- [WebKit Content Blockers](https://webkit.org/blog/3476/content-blockers-first-look/)
- [Apple: Content-Blocker-Regeln](https://developer.apple.com/documentation/safariservices/creating-a-content-blocker)
- [SponsorBlock Hash-Präfix-Prinzip](https://github.com/ajayyy/SponsorBlock/wiki/K-Anonymity)
- [SponsorBlock-Datenlizenz](https://github.com/ajayyy/SponsorBlock/wiki/Database-and-API-License)
- [SponsorBlock-Datenschutz](https://wiki.sponsor.ajay.app/w/SponsorBlock%3APrivacy_policy)
- [SponsorBlock-API-Dokumentation](https://wiki.sponsor.ajay.app/w/API_Docs)
- [Return YouTube Dislike: Abruf](https://www.returnyoutubedislike.com/docs/fetching)
- [Return YouTube Dislike: Attribution und Rate-Limits](https://www.returnyoutubedislike.com/docs/usage-rights)

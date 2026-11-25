# Bekannte Grenzen und offene Abnahme

Stand: 25. November 2026. **Die iOS-App ist noch nicht vollständig gebaut und praktisch abgenommen.** Produktionscode, portable Core-Tests, JavaScript-Fixtures und echte App-Ausführung sind unterschiedliche Nachweisstufen. Die [Feature-Paritätsmatrix](FEATURE-PARITY.md) enthält jede der 163 Android-Funktions-IDs; dieses Dokument fasst die wesentlichen offenen Punkte zusammen.

## 1. Was tatsächlich geprüft wurde

41 Foundation-XCTest-Fälle sind mit Swift 6.4.3 auf Linux bestanden: Linkrouter, Präsentationszustand, atomische Dateien, gemeinsame Inbox, Wiedergabe-Wiederherstellungsspeicher und Release-Metadaten. Das portable Package umfasst sechs Produktionsdateien. Die MediaBridge-Verhaltenstests und Filter-/Vendor-Fixtures wurden mit Node ausgeführt. Weitere Xcode-XCTest- und UI-Testdateien liegen als Quellcode vor.

**Nicht ausgeführt:** vollständiges Xcode-Build/Linking, App-/Extension-Signierung, iOS-Simulator, echtes iPhone/iPad, installierte Share Extension, App-Intent-Handoff, Live-YouTube, hörbare Shorts, System-PiP, Google-OAuth-Ende-zu-Ende, reale Data-API-Kontoaktionen und WebKit-Filterwirkung. Auch der lokale Shields-Testbildschirm ist noch nicht in iOS gelaufen. Ein Swift-Syntaxparse ist kein Apple-SDK-Typecheck. Details und Befehle stehen in [TESTING.md](../TESTING.md) und [ADBLOCK-VALIDATION.md](ADBLOCK-VALIDATION.md).

## 2. Noch nicht vollständig implementierte Android-Parität

Diese Punkte sind technisch umsetzbare Restarbeit. Sie werden nicht als unvermeidliche iOS-Plattformgrenze ausgegeben.

| Matrix-ID | Stand | Konkreter Rest |
| --- | --- | --- |
| DIAG-01/02 | In Entwicklung | Begrenzte feste Lifecycle-/Medienereignisse mit ready/network/error-Zuständen sind vorhanden. Szenen, Webansichten und angeforderte App-Pausen werden lokal erfasst. Eine fremde Website-Pause lässt sich anhand eines Media-Events allein nicht eindeutig zuordnen. Der Grund einer Website-Pause wird nicht erfunden. |
| DIAG-04 | In Entwicklung | Home zeigt Fehler/Retry und eine Erklärung der getrennten Sitzungen. Die Diagnose zeigt Netz- und Ladezustand, Herkunft, Routing, Retry und Browservergleich. Die Anzeige wartet auf praktische Abnahme. |

Weitere begrenzte Abweichungen stehen direkt in den jeweiligen Matrixzeilen. Dazu zählen etwa iOS-Timeline-Maße statt identischer dp-Werte, native Controls als Ersatz für einzelne DOM-Einblendungen und vom Betriebssystem verwaltete Ausrichtungsereignisse statt eines eigenen Android-Sensorfilters. Ein solcher dokumentierter Ersatz ist erst nach praktischer Nutzungsprüfung akzeptiert.

## 3. Vorhandene Implementierung mit noch unbestätigtem Laufzeitverhalten

### Player, Mini und Gesten

Die App hält den Watch-Player, verändert Mini über native Geometrie und schützt asynchrone Befehle mit Quelle, Generation und Elementidentität. Fokussiertes Pinch skaliert nur das Video. Native Controls-Rechtecke begrenzen die Gestenerkennung; Originalsteuerung, native Timeline und Mini-Aktionen bleiben eigene Ziele.

Das beweist noch keine visuell saubere Animation oder kontinuierliche Audioausgabe. Reale Prüfungen müssen mindestens schnelle Watch→Mini→Watch-Wechsel, beide Querformate, manuelles Verlassen von Vollbild, zweite Videoauswahl während eines alten Seek, pausierte Wiedergabe, unterschiedliche Seitenverhältnisse, bereits gezoomte Inhalte, Hintergrund/Sperrbildschirm und PiP abdecken. DOM-Fixtures können weder WebKit-Compositing noch aktuelle YouTube-Reaktionen auf Größen-/Sichtbarkeitsänderungen simulieren.

Der native Wiederherstellungsspeicher ist automatisiert getestet. Die vollständige App-Integration „letzte Auswahl minimiert und pausiert, neuer externer Link gewinnt“ ist geschrieben, aber noch nicht im echten Prozessneustart geprüft. Ebenso sind Idle-Timer-/Renderer-Recovery-Integrationen und der automatische einmalige Werbe-Recoverypfad erst Quellcode, keine Geräteergebnisse.

### Shorts und Zugriffshilfen

Die Tests bestätigen Sichtbarkeitsauswahl, einen hörbaren Dokumentbesitzer, Nutzer-Mute, begrenzte Startversuche und das Ablehnen alter Seek-Ziele in einer kontrollierten Umgebung. Sie bestätigen keinen Lautsprecherton oder einen fehlerfreien aktuellen YouTube-Shorts-Feed. Verweigertes Autoplay benötigt weiter eine wirkliche Nutzeraktion.

Labels, 44-pt-Bedienflächen, VoiceOver-Anpassaktionen, Tastatur-Seeks, Systemschriftstile und Reduce-Motion-Zweig sind vorhanden. Vollständige VoiceOver-Reihenfolge, großer Dynamic Type, Switch Control, Hardwaretastatur, externe Displays, iPad-Split-View/Stage Manager und alle Fenstergrößen sind noch nicht praktisch abgenommen. Es gibt keine Behauptung vollständiger Barrierefreiheit.

### AdBlock

WebKit-Regeln, Dokumentstart-Scriptlets, JSON-/fetch-/XHR-Pruning und kosmetische Regeln werden im Code eingerichtet. Tatsächlich ausgeführte Node-Fixtures decken positive und negative Gegenfälle, vorhandene Originalsignatur und Manipulation, sichere Auth-/Medienpfade und Vendor-Reproduzierbarkeit ab. Der Swift-Security-/WKContentRuleList-Compilerpfad wurde nicht mit Apple-SDK ausgeführt.

Die letzte gute Regelliste bleibt bei gescheiterter Kompilierung/Signatur erhalten. Neue Document-Start-Hooks gelten jedoch erst nach Neuladen des betroffenen Dokuments; bestehende Hooks lassen sich nicht rückwirkend als vollständig entfernt darstellen. Die Oberfläche macht den nötigen Reload kenntlich. Ads, die die geprüften Regeln nicht erkennen, können weiterhin erscheinen. Ein erkannter Werbezustand kann Playback anhalten; der begrenzte Recoveryversuch und eine Fehlermeldung sind keine Zusage störungsfreier werbefreier Wiedergabe.

Der lokale Shields-Test verwendet synthetische lokale Ressourcen und synthetische Testregeln. Ein später erfolgreicher Lauf beweist den getesteten WebKit-Mechanismus, nicht die Filterung jeder echten YouTube-Werbevariante. Die Anzahl kompilierter Regeln ist kein Netzwerk-Blockzähler. Öffentliche WKContentRuleList-APIs liefern dafür keine einfache vollständige Request-Trefferstatistik. [Apple: WKContentRuleListStore](https://developer.apple.com/documentation/webkit/wkcontentruleliststore), [WebKit: Content Blockers](https://webkit.org/blog/3476/content-blockers-first-look/).

### Communitydienste und API-Konto

SponsorBlock-/RYD-Reducer, Parser, Caches, Requestgrenzen und native Oberflächen sind vorhanden. Ihre zusätzlichen XCTest-Fälle wurden ohne Apple-SDK nicht ausgeführt. Echtzeitverhalten, serverseitige Antworten, Retry-After, Opt-out während Netzwerkwechsel und Cachekonkurrenz benötigen weiter gezielte Tests. Kein Dienst erhält Kontotokens oder Website-Cookies. SponsorBlock-Vorschläge können unvollständig/falsch sein; RYD-Werte sind ausdrücklich Schätzungen.

Kontologik, PKCE-/Payloadtests und echte API-Endpunkte sind vorhanden. Reale Read-/Write-Abläufe wurden nicht im Nutzerkonto ausgeführt. Ein Datenmodell oder eine erfolgreiche Unit-Test-Payload ist kein Nachweis, dass Google-Consent, Projektquota, private Videos und sämtliche Kontoaktionen aktuell auf dem Gerät funktionieren.

## 4. Tatsächliche Plattform- und Dienstgrenzen

| Bereich | Grenze | Vorhandene unterstützte Alternative |
| --- | --- | --- |
| Google im eingebetteten Browser | Google erlaubt seinen OAuth-Flow nicht in beliebigen eingebetteten User-Agents. Ein nativer API-Grant erzeugt keine authentifizierte YouTube-Website im WKWebsiteDataStore. | Systemauthentifizierung, native Data-API-Kontoansichten und klare getrennte Website-Erklärung. Keine Cookie-/Passwortübertragung. [Google OAuth](https://developers.google.com/identity/protocols/oauth2/native-app#disallowed_useragent), [iOS API access](https://developers.google.com/identity/sign-in/ios/api-access). |
| Erzwungene YouTube-Qualität | Die aktuelle öffentliche IFrame-API bietet keine verlässlich erzwingbare Qualitätsauswahl wie Androids undokumentierte Website-Methoden. | Originale YouTube-Steuerung; bei erlaubten Direktmedien AVPlayer-Auflösungspräferenz ohne Erfolgsgarantie. [YouTube IFrame API](https://developers.google.com/youtube/iframe_api_reference). |
| Systemlautstärke | Systemlautstärke ist kein frei setzbarer öffentlicher App-Parameter. Private Slider-Tricks werden nicht verwendet. | Geste öffnet den vom Nutzer bedienten MPVolumeView. [Apple: MPVolumeView](https://developer.apple.com/documentation/mediaplayer/mpvolumeview). |
| System-PiP | Apple-PiP kann nicht als beliebige Verkleinerung einer gesamten Android-artigen Browseraktivität umgesetzt werden. Webmedien müssen die Fähigkeit tatsächlich anbieten. | AVPictureInPictureController für AVPlayerLayer; WebKit/HTMLVideo-Präsentationsmodus nur nach Capabilityprüfung. Keine Zusage für jedes YouTube-Video. [Apple: AVPictureInPictureController](https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller). |
| Fremde Universal Links | Die App kontrolliert die Domain youtube.com und deren Associated-Domain-Datei nicht. | Share Extension, Link-Eingabe, Custom Scheme, App Intent/Kurzbefehl. [Apple: Supporting associated domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains). |
| Share Extension → Host | Eine Share Extension hat keinen allgemeinen unterstützten Freibrief, ihre Host-App über private Responder-Ketten zu starten. | Validierte App-Group-Inbox; Nutzer öffnet Weiktube bzw. nutzt App Intent/Kurzbefehl. [Apple: App Extension Programming Guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionOverview.html). |
| Watch Later / Google-Verlauf | Die YouTube Data API stellt diese früheren Systemlisten nicht als regulär abrufbare Playlistfunktion bereit. | Eigene Playlists und unabhängiger lokaler Weiktube-Verlauf. [YouTube API revision history](https://developers.google.com/youtube/v3/revision_history). |
| APK-Selbstupdate | Android-Paket-/ABI-/Installerabläufe sind kein iOS-Installationsmechanismus. | Öffentliche Releaseinformationen und echte Apple-Signierungs-/Xcode-/TestFlight-/Storewege; kein unsigniertes Selbstinstallieren. |

Diese Grenzen rechtfertigen nicht, andere technisch mögliche Funktionen wegzulassen. Die konkreten Restarbeiten aus Abschnitt 2 behalten ihren Entwicklungsstatus.

## 5. Externe Konfiguration und Veröffentlichung

Für einen echten Gerätebuild fehlen reale Apple-Team-/Bundle-/App-Group-Zuordnungen und die daraus erzeugte Signierung. Für Kontofunktionen fehlen die reale iOS-OAuth-Clientregistrierung, ihre Redirect-URI und das passend eingerichtete Google-Projekt. Platzhalter sind nicht als funktionierende Zugangsdaten einzutragen. Details: [BUILD.md](../BUILD.md), [INSTALLATION.md](../INSTALLATION.md).

Der App-Releasechecker ist implementiert und unterscheidet bestätigte Metadaten, Netzwerkfehler, Rate-Limit und nicht öffentlich abrufbare Releases. Das Zielrepository `weikiboy-tech/Weiktube-ios` existiert inzwischen; für diesen Quellstand wurde kein iOS-Release veröffentlicht. Eine spätere private Bereitstellung ist ohne Repository-Zugangsdaten für den öffentlichen Checker nicht abrufbar. Ein HTTP 404 darf deshalb nicht in „aktuell“ umgedeutet werden. Ein App-Release ist nicht dasselbe wie der bereits existierende signierte Android-Filterrelease.

Der iOS-Quellcode wird im öffentlichen Repository [weikiboy-tech/Weiktube-ios](https://github.com/weikiboy-tech/Weiktube-ios) auf dem Branch `main` entwickelt.

Ein vollständiger Abschluss erfordert den ganzen Xcode-Build, installierte Extension/Intents, Medien-/Konto-/Filterabnahme mit dokumentiertem Gerät und die bewusste Entscheidung über alle verbliebenen Paritätsabweichungen. Ein TestFlight-/Store-Upload oder eine Zulassung ist nicht zugesagt.

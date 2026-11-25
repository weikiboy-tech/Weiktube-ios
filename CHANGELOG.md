# Changelog

## 0.1.0-dev — 2026-11-25

Erster eigenständiger nativer iOS-/iPadOS-Quellstand von Weiktube. Aktuelle Build- und Simulatorergebnisse stehen in [TESTING.md](TESTING.md). Android 1.3.23 / Commit `a7e0a9221e73d3d9c361f614adcb9e027fb70c35` ist die Funktionsreferenz.

### Hinzugefügt

- SwiftUI-App mit der ursprünglichen Tabfolge, Weiktube-Farben/-Logo, iPhone-/iPad-Konfiguration, nativen Einstellungen, Verlauf und Kontoansichten.
- Dauerhafte Home-/Watch-/Shorts-WKWebViews mit sicherem Routing, eigenem Bridge-Content-World, kontrolliertem Medienbesitz, Originalcontrols und begrenzter Recovery.
- Gemeinsamer Player-Präsentationszustand für Vollbild, Mini und bestätigten PiP; Video-Pinch, Doppeltipp, temporäres Tempo, Helligkeit, native Systemlautstärke und eigene interaktive Timeline.
- Öffentliche AVPlayer-Wiedergabe für ausdrücklich eingegebene zulässige HTTPS-Direktmedien, Medienauswahl und native PiP-Anbindung.
- Shorts-Timeline, sichtbare Audio-/Autoplayaktionen, Elementidentität und Schutz gegen veraltete Befehle.
- WebKit-Contentregeln, gepinnte AdGuard-Scriptlets mit vollständiger Herkunft, kosmetische Regeln, Custom-Domains/Ausnahmen und signierte Filterupdates.
- SponsorBlock mit acht Kategorien, Hashpräfixabfragen, manuellen/automatischen Skipaktionen, bestätigter Zählung, Undo, lokalen Statistiken und begrenztem Cache.
- Optionale RYD-Schätzungen mit Cache, Rate-Limit, Identitätsprüfung und Kennzeichnung neben dem erkannten Dislike-Button.
- System-Google-OAuth mit PKCE/State/Keychain und getrennten Lese-/Schreibfreigaben; native Abos/Feed, Playlists, Bewertungen, Kommentare/Antworten und Speichern.
- Lokale atomische Persistenz, Verlaufskarussell, sichere pausierte Wiederherstellung und Schutz gegen späte Callbacks nach Datenlöschung.
- Share Extension mit App-Group-Inbox, Custom URL Scheme und App Intents/Kurzbefehlen.
- Lokale Diagnose, Datenschutz-/Lizenzansichten, öffentliche Release-Metadatenprüfung ohne automatische Installation.
- Xcode-Projekt mit vier Targets und gemeinsamem Scheme, Debug/Release-Konfiguration, Iconressourcen, Privacy Manifest und macOS-GitHub-Actions.
- Vollständige Paritätsmatrix für 163 Android-Funktions-IDs mit Implementierungsdateien, Teststand und konkreten Grenzen.

### Im Entwicklungsstand korrigiert

- Sequenzierte Abgabe/Übernahme der Audioberechtigung vor einem neuen Start; kein verspäteter Play-Auftrag nach Pause.
- Resume-/Sponsor-Seeks zählen erst nach bestätigtem tatsächlichem Ziel; Video-/Elementwechsel verwerfen alte Ergebnisse.
- Explizite Linkzeitstempel und gespeicherte Positionen bleiben während Laden und Werberecovery erhalten.
- Wiederhergestellter Miniplayer startet pausiert, aktiviert die Audio-Session nicht selbst und blockiert keine neuen Shorts.
- Löschen/Deaktivieren des Verlaufs gewinnt gegen alte Speicher- und Startup-Rückmeldungen.
- Consent-Abbruch erzeugt keine Schreibfreigabe und verwirft keine weiterhin gültige Leseberechtigung.
- Öffentliche Serviceantworten sind größenbegrenzt; zurückgewiesene Transfers werden beendet.
- Releasefehler/404/gespeicherte Metadaten werden von einem bestätigten aktuellen Versionsstand unterschieden.

### Tatsächliche Prüfung und offene Freigabe

41 portable Foundation-XCTest-Fälle bestanden mit 0 Fehlern; 68 JavaScript-Medien-Assertions, Filter-Fixtures und Projektstruktur wurden geprüft. Die ausführlichen Belege und jüngeren Apple-Prüfläufe stehen in [TESTING.md](TESTING.md). Es gibt keine behaupteten FPS-/RAM-Werte, keine Live-AdBlock-Garantie und keinen behaupteten CI-Pass.

Noch umzusetzende oder unbestätigte Paritätsdetails sowie echte Apple-/Google-Grenzen stehen in [FEATURE-PARITY.md](docs/FEATURE-PARITY.md) und [KNOWN-LIMITATIONS.md](docs/KNOWN-LIMITATIONS.md). Dieser Eintrag ist kein öffentliches GitHub-Release.

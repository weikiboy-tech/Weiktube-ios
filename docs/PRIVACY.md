# Datenschutz und Datenflüsse

Stand: **25. November 2026**. Dieses Dokument beschreibt den vorliegenden iOS-Quellcode. Es ist die technische Datenschutzbeschreibung für den Entwicklungsstand; eine veröffentlichte App benötigt dazu passende Betreiberangaben, erreichbare Datenschutz-/Supportseiten und die tatsächlich geprüften Distributionsangaben.

Weiktube betreibt in diesem Stand keinen eigenen Backenddienst, keine eigene Nutzungsanalyse und keinen automatischen Diagnoseupload. YouTube, die optionalen Communitydienste und angefragte öffentliche Medienhosts bleiben externe Dienste und erhalten die für ihre Netzwerkverbindungen notwendigen Daten. „Lokal gespeichert“ bedeutet deshalb nicht „die App verwendet kein Netzwerk“.

## Netzwerkverbindungen

| Funktion | Empfänger | Anlass und übertragene Daten | Steuerung |
| --- | --- | --- | --- |
| Originale YouTube-Seiten | YouTube/Google und von diesen Seiten geladene Ressourcen | Angeforderte Seite, Such-/Video-/Kanal-/Playlist-Parameter, IP-Adresse, Browser-/Netzwerkinformationen und bestehende Website-Sitzung | Startseite/Shorts/Watch; Filter können passende Ressourcen begrenzen, keine Garantie vollständiger Isolation |
| Native Google-Freigabe | `accounts.google.com`, `oauth2.googleapis.com` | Registrierter Client, Redirect, angeforderte Scopes, PKCE-Challenge/Verifier und State; Code-/Tokenaustausch in der nativen OAuth-Komponente | Bewusster Kontoeinstieg über die Systemanmeldung |
| Native Kontodaten/-aktionen | `www.googleapis.com/youtube/v3` | Nur angeforderte API-Ressource bzw. ausdrücklich ausgelöste Aktion; OAuth-Bearer-Token nur an erlaubte Google-Endpunkte | Lesezugriff und explizites Upgrade für Interaktionen getrennt |
| Öffentliche Vorschaubilder | Validierte Google-/YouTube-Bildhosts | Angefragte öffentliche Bildadresse und IP-Adresse; keine OAuth-Header oder Website-Cookies | Beim Anzeigen entsprechender Listen; begrenzter Download/Cache |
| SponsorBlock | `sponsor.ajay.app` | Vierstelliger SHA-256-Präfix der Video-ID und Kategorien; technisch IP-Adresse und Requestmetadaten | Standardmäßig **aus**, eigener Schalter und Hinweise |
| Return YouTube Dislike | `returnyoutubedislikeapi.com` | Öffentliche Video-ID und Requestmetadaten/IP-Adresse | Standardmäßig **aus**, eigener Schalter und Hinweise |
| Signierte Filterupdates | Gepinnter Filterrelease im Android-Repository bei GitHub; erlaubte GitHub-Releasehosts bei Redirect | Feste Filterdatei-/Signaturadresse und Requestmetadaten, keine Video-ID oder Google-Anmeldedaten | Manuell bzw. standardmäßig tägliche Prüfung, getrennt deaktivierbar |
| iOS-Releaseinformationen | `api.github.com/repos/weikiboy-tech/Weiktube-iOS/releases/latest` | Feste Repositoryadresse und öffentliche App-Version im User-Agent; keine GitHub-/Google-Zugangsdaten | Automatische Prüfung standardmäßig **aus**, manuell verfügbar; keine automatische Installation |
| Eingegebenes Direktvideo / Zusatzbrowser | Vom Nutzer ausdrücklich gewählter validierter HTTPS-Host und seine Inhalte | Medien-/Seitenadresse und technische Requestdaten | Nutzeraktion; AVPlayer extrahiert keine geschützten YouTube-Streams |

SponsorBlock-Präfixabfragen verringern die direkt mitgeteilte Videoidentität; sie bieten keine Zusage vollständiger Anonymität. Die Abfrage übermittelt keine Google-Tokens und keine Segmentabstimmungen oder Nutzungsstatistiken. Die genaue API ist in den [offiziellen SponsorBlock-API-Dokumenten](https://wiki.sponsor.ajay.app/w/API_Docs) und der [K-Anonymity-Beschreibung](https://github.com/ajayyy/SponsorBlock/wiki/K-Anonymity) erklärt. Hinweise des Anbieters: [SponsorBlock-Datenschutz](https://wiki.sponsor.ajay.app/w/SponsorBlock%3APrivacy_policy).

RYD ist ein optionaler Schätzdienst. Weiktube fragt Werte ab, führt keine RYD-Nutzerregistrierung durch und sendet keine Like-/Dislike-Abstimmung an RYD. Der Anbieter beschreibt Datenbasis, Attribution und API-Limits in seinem [offiziellen Repository](https://github.com/Anarios/return-youtube-dislike) und den [API-Nutzungsbedingungen](https://www.returnyoutubedislike.com/docs/usage-rights). Native Google-Bewertungen gehen nach gesonderter Nutzeraktion an die YouTube Data API.

## Getrennte Google- und Website-Sitzungen

Die native OAuth-Freigabe liegt in der Keychain. Die Webansichten teilen den persistenten `WKWebsiteDataStore.default()`. Diese beiden Bereiche werden nicht verbunden: Es gibt keine Übertragung von Google-Passwörtern, OAuth-Tokens oder Safari-Cookies in die YouTube-Seite.

Die App verhindert Google-OAuth-Navigation in eingebetteten Ansichten und bietet die native Systemanmeldung an. Dies entspricht der Vorgabe für sichere User-Agents in [Googles OAuth-Richtlinien](https://developers.google.com/identity/protocols/oauth2/policies). Eine native Anmeldung erzeugt daher keine angemeldete Original-YouTube-Startseite. Native Abos und Playlists verwenden die offizielle API.

Zugangsdaten werden in der Keychain mit `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` abgelegt. Die App implementiert keine eigene Passwortmaske und speichert keinen Client-Secret. Konto- und Scopewechsel invalidieren laufende Arbeit über eine Sitzungsrevision. Ein abgebrochener Schreib-Consent darf eine noch gültige Lesefreigabe nicht als neue Schreibberechtigung behandeln.

Abmeldung, Entzug der Google-Freigabe und Löschen der Website-Daten sind verschiedene Vorgänge. Ein fehlgeschlagener Remote-Widerruf darf nicht als erfolgreich gelten; die Kontooberfläche beschreibt den tatsächlichen Stand und den Weg zu [Google-Verbindungen](https://myaccount.google.com/connections). Ein begrenzter ausstehender Widerruf wird ausschließlich geschützt und nur zur ausdrücklich ausgelösten Wiederholung aufbewahrt; Details und Ergebnis stehen in der Kontoansicht.

## Lokale Daten

| Datentyp | Speicherort / Begrenzung | Entfernen oder Wirkung |
| --- | --- | --- |
| Einstellungen | App-eigene UserDefaults; validierte Auswahlwerte, begrenzte JSON-Größe | Änderungen lokal; keine eigene Synchronisation |
| Normaler Videoverlauf | Atomische JSON-Datei im Application-Support-Verzeichnis, maximal 100 Einträge; Karussell maximal 12 | Einzelnes Entfernen oder gesamter Verlauf in „Du“/Einstellungen |
| Wiedergabepositionen | Bestandteil des Verlaufs; ungültige/loading/ad-Werte dürfen gute Position nicht ersetzen | Verlauf löschen/deaktivieren verhindert neue Fortschrittswrites dieser Auswahl |
| Letzte Playerauswahl | Eigene atomische Datei, maximal 16 KiB, maximal sieben Tage gültig | Pausierte Wiederherstellung; explizites Schließen oder Löschen/Deaktivieren des Verlaufs entfernt sie |
| Direkte Medienlinks | Validierte URL im lokalen Verlauf/letzter Auswahl, falls Verlauf aktiv | Durch Verlaufslöschung entfernbar; eingegebene Queryparameter können Bestandteil dieser URL sein |
| Geteilte/importierte Links | App-Group-Datei, maximal 20 Einträge und sieben Tage | Erst nach erfolgreichem Routing bestätigen; neue zwischenzeitliche Zustellungen bleiben erhalten |
| Website-Daten | Von WebKit verwalteter persistenter Website-Speicher | „Website-Daten löschen“ entfernt Cookies, Cache und Website-Speicher in Weiktube |
| SponsorBlock-Daten | Begrenzter öffentlicher Cache mit 64 Einträgen, Ablauf je nach Ergebnis; lokale Einstellungen/Skipstatistik | Eigene Cache-/Statistikaktionen; Abschalten beendet die Verwendung |
| RYD-Daten | Öffentlicher Cache mit maximal 200 Einträgen, normalerweise eine Stunde für verfügbare Werte, kurze Negativcachezeit | Eigene Cacheaktion; Abschalten entfernt die aktive Anzeige und beendet Requests |
| Requestbudget / Backoff | Kleine lokale Zähler/Zeiten | Cache leeren umgeht keine Server-Rate-Limits |
| Filterdaten | Gebündelte Regeln und letzte gültige signierte Daten; geprüfte Grenzen und Version | Ungültiges Update ersetzt die letzte gute Konfiguration nicht |
| Releaseinformationen | Validierter Metadatencache bis 512 KiB und 30 Tage; Datum/Ergebnis letzter Prüfung | Alte Daten bleiben als gespeichert gekennzeichnet, kein erfundener aktueller Stand |
| Diagnose | Maximal 200 feste Ereignisse im Arbeitsspeicher | Lokal löschen; Export ausschließlich über bewusste Teilen-Aktion |

Atomische App-Dateien verwenden die im Quellcode konfigurierte iOS-Dateischutzklasse. Die App bietet keine eigene Cloud-Synchronisation. Normale Geräte-/Systembackups können lokale App-Daten abhängig von den Geräteeinstellungen einschließen; „lokal“ ist keine Zusage, dass Betriebssystembackups ausgeschlossen sind. Die gewählte Keychain-Schutzklasse ist gerätegebunden.

## Bridge, Requests und Diagnose

Die Medienbridge läuft im eigenen WebKit-Content-World, akzeptiert Main-Frame-Nachrichten nur aus den erlaubten HTTPS-Ursprüngen und prüft Nachrichtenschema, Dokumenttoken, Generation, Video- und Elementidentität. Befehle erhalten validierte Argumente; eine beliebige übergebene URL wird nicht als ausführbares JavaScript zusammengesetzt. Veraltete Mediencallbacks dürfen weder eine neue Quelle steuern noch einen SponsorSkip zählen.

Öffentliche Serviceclients verwenden getrennte, cookielose URLSessions ohne Credential-Storage. Hosts, HTTPS, Ports, Weiterleitungen, Antwortgrößen und JSON-Schema werden geprüft; abgebrochene oder zu große Transfers werden beendet. Es gibt keine Weitergabe des Google-Tokens an SponsorBlock, RYD, GitHub oder Thumbnailhosts.

Diagnoseeinträge enthalten feste Ereignisnamen und begrenzte technische Medienzustände. Sie enthalten keine URLs, Video-IDs, Seitentexte, Cookies, Tokens, Kontonamen oder rohe API-Antworten. Der Bericht verlässt die App erst, wenn der Nutzer ihn über die systemeigene Teilen-Funktion weitergibt. Die App sendet ihn nicht automatisch an ein Supportkonto.

Filterupdates erlauben nur geprüfte Daten, keine neue beliebige JavaScript-Ausführung aus einer heruntergeladenen Regeldatei. Die appseitigen Scriptlets stammen aus den beigefügten gepinnten Quellen. Signatur, Versionsschutz, Größenlimit und letzter guter Stand werden separat geprüft.

## Apple-Manifest und Freigabe

`Weiktube/PrivacyInfo.xcprivacy` enthält für den vorliegenden eigenen Code `NSPrivacyTracking = false`, keine eigenen Trackingdomains und den UserDefaults-Verwendungsgrund `CA92.1`. Die Manifestdatei ist Teil der App-Ressourcen. Sie behauptet nicht, dass YouTube oder andere angefragte Dienste keine Daten verarbeiten.

Vor einer Distribution sind das **tatsächlich erzeugte App-/Extension-Bundle**, darin verwendete APIs, die endgültigen Datenflüsse, App-Store-Connect-Datenschutzangaben und Betreiberinformationen zu überprüfen. Neue Funktionen oder SDKs können andere Angaben erfordern. Apples [Dokumentation zu Required-Reason-APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) beschreibt die Pflicht, den wirklichen Verwendungsgrund korrekt anzugeben.

Die Dokumentation und der Quellcode ersetzen keine noch ausstehende Geräte-/Netzwerkabnahme. Welche Prüfungen real ausgeführt wurden, steht ausschließlich in [TESTING.md](../TESTING.md).

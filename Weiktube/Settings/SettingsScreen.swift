// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

@MainActor
struct SettingsScreen:View {
    @ObservedObject var app:AppModel
    @ObservedObject private var settings:AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var clearHistory=false
    @State private var clearWebsite=false
    init(app:AppModel){self.app=app;settings=app.settings}
    var body:some View {
        Form {
            Section("Erscheinungsbild") {
                Picker("Design",selection:$settings.appearance){ForEach(AppAppearance.allCases){Text($0.title).tag($0)}}
            }
            Section("Player und Gesten") {
                Toggle("Helligkeit links wischen",isOn:$settings.brightnessGesture)
                Toggle("Lautstärkeregler rechts öffnen",isOn:$settings.volumeGesture)
                Text("iOS erlaubt keine programmgesteuerte Änderung der Systemlautstärke. Die Geste zeigt den nativen Lautstärkeregler.").font(.footnote).foregroundStyle(.secondary)
                Toggle("Doppeltipp zum Spulen",isOn:$settings.doubleTapSeek)
                Picker("Sprungweite",selection:$settings.seekSeconds){ForEach(AppSettings.seekChoices,id:\.self){Text("\($0) Sekunden").tag($0)}}
                Toggle("Gedrückt halten für Tempo",isOn:$settings.holdToSpeed)
                Picker("Temporäre Geschwindigkeit",selection:$settings.holdSpeed){ForEach(AppSettings.holdChoices,id:\.self){Text("\($0.formatted())×").tag($0)}}
                Text("Helligkeit, Lautstärke und Gedrückthalten gelten im Vollbild. Ziehe den Player im Hochformat nach unten, um ihn zu verkleinern. Pinch vergrößert ausschließlich das Video (1–8×).").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Videoqualität") {
                qualityPicker("Im WLAN",value:$settings.wifiQuality)
                qualityPicker("Bei mobilen Daten",value:$settings.mobileQuality)
                Text("Direkte AVPlayer-Videos erhalten diese Auflösungspräferenz. YouTube entscheidet selbst: Wähle die Qualität in der originalen Videosteuerung. Eine gespeicherte Präferenz ist dort keine bestätigte Qualitätsänderung.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Schutz und Community-Daten") {
                Toggle("Filterupdates täglich prüfen",isOn:$settings.automaticFilterUpdateChecks)
                NavigationLink("Adblock"){AdBlockScreen(service:app.adBlock,onReloadPages:app.reloadPages)}
                NavigationLink("SponsorBlock"){SponsorBlockSettingsScreen(service:app.sponsor)}
                NavigationLink("Return YouTube Dislike"){ReturnDislikeSettingsScreen(service:app.dislikes)}
            }
            Section("Verlauf und Website-Daten") {
                Toggle("Verlauf speichern",isOn:$settings.saveHistory)
                Button("Verlauf und Wiedergabepositionen löschen",role:.destructive){clearHistory=true}
                Button("Website-Daten löschen",role:.destructive){clearWebsite=true}
                Text("Website-Daten, lokaler Verlauf und die Google-API-Freigabe sind getrennt. Es werden keine Cookies ausgelesen oder in Berichte kopiert.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Links und Kurzbefehle") {
                NavigationLink("In Weiktube öffnen"){LinkHelpScreen()}
            }
            Section("Diagnose und Informationen") {
                NavigationLink("Lokale Diagnose"){DiagnosticsScreen()}
                NavigationLink("Datenschutz & Lizenzen"){PrivacyScreen()}
                NavigationLink("Version & Installation"){InstallationScreen()}
                NavigationLink("App-Updates"){ReleaseUpdatesScreen(checker:app.releaseChecker,settings:settings)}
                if let error=settings.storageError{Text(error).foregroundStyle(.orange)}
            }
        }.navigationTitle("Einstellungen").tint(.weiktubeAccent)
            .toolbar{ToolbarItem(placement:.cancellationAction){Button("Fertig"){dismiss()}}}
            .confirmationDialog("Verlauf löschen?",isPresented:$clearHistory,titleVisibility:.visible){
                Button("Verlauf löschen",role:.destructive){app.clearHistory()};Button("Abbrechen",role:.cancel){}
            }
            .confirmationDialog("Website-Daten löschen?",isPresented:$clearWebsite,titleVisibility:.visible){
                Button("Website-Daten löschen",role:.destructive){Task{await app.clearWebsiteData()}};Button("Abbrechen",role:.cancel){}
            } message:{Text("Dies schließt den Player und entfernt Cookies, Cache und Website-Speicher aus Weiktube.")}
    }
    private func qualityPicker(_ title:String,value:Binding<Int>)->some View {
        Picker(title,selection:value){ForEach(AppSettings.qualityChoices,id:\.self){Text($0 == 0 ? "Automatisch":"\($0)p").tag($0)}}
    }
}

struct LinkHelpScreen:View {
    var body:some View {
        List {
            Section("Teilen") {Text("Wähle in YouTube oder Safari „Teilen“ → „Weiktube“. Der Link wird sicher vorgemerkt. Öffne danach Weiktube, um ihn zu laden.")}
            Section("Kurzbefehle") {Text("Füge die Aktion „In Weiktube öffnen“ zu einem Kurzbefehl hinzu und übergib einen YouTube-Link. Die Aktion öffnet die App über den vorgesehenen App-Intent-Weg.")}
            Section("URL-Scheme") {Text("weiktube://open?url=<URL-kodierter YouTube-Link>").font(.footnote.monospaced()).textSelection(.enabled)}
            Section("iOS-Linkzuordnung") {Text("Weiktube kann fremde Universal-Link-Domains wie youtube.com nicht systemweit übernehmen. Verwende das Teilen-Menü, die Link-Eingabe oder Kurzbefehle.")}
        }.navigationTitle("Links öffnen")
    }
}
struct PrivacyScreen:View {
    var body:some View {
        List {
            Section("Deine Daten") {Text("Weiktube sendet keine eigene Telemetrie. Verlauf, Positionen und Einstellungen bleiben lokal. Google-Tokens werden im Schlüsselbund gespeichert. Die YouTube-Webseiten verbinden sich mit Google und verwenden ihren eigenen Website-Speicher.")}
            Section("Freiwillige Dienste") {Text("SponsorBlock erhält nach Aktivierung einen vierstelligen SHA-256-Präfix der Video-ID sowie technisch bedingt die IP-Adresse. Return YouTube Dislike erhält nach Aktivierung die öffentliche Video-ID und IP-Adresse. Beide erhalten keine Google-Tokens oder Cookies.")}
            Section("Filter") {Text("Filterupdates verwenden signierte, begrenzte Datendateien. Filterwirkung hängt von der Website und der WebKit-Unterstützung ab. Es gibt keine Zusage vollständiger Werbefreiheit.")}
            Section("Lizenzen") {
                Text("Weiktube: GPL-3.0-only. Android-Referenz: weikiboy-tech/Weiktube 1.3.23. AdGuard Scriptlets 2.5.1: © Adguard Software Ltd. und Mitwirkende, GPL-3.0. SponsorBlock-Community-Daten: CC BY-NC-SA 4.0.")
                NavigationLink("GNU GPL Version 3"){BundledTextScreen(name:"LICENSE",title:"GPL-3.0")}
                NavigationLink("Drittanbieter-Hinweise"){BundledTextScreen(name:"THIRD-PARTY-NOTICES",extensionName:"md",title:"Drittanbieter")}
            }
        }.navigationTitle("Datenschutz & Lizenzen")
    }
}
struct InstallationScreen:View {
    var body:some View {
        List {
            Section("Installierte Version") {
                LabeledContent("Weiktube",value:Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unbekannt")
                LabeledContent("Build",value:Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unbekannt")
            }
            Section("Entwicklungsversion") {
                Text("Diese Ausgabe wird mit Xcode und deiner Apple-Signierung installiert. Neue Builds werden über Xcode eingespielt. TestFlight erfordert eine eingerichtete Apple-Developer-Mitgliedschaft und einen hochgeladenen Build.")
                Text("Eine unsignierte Build-Datei ist nicht direkt auf einem iPhone installierbar. Updates dürfen den Signatur- und Distributionsweg von iOS nicht umgehen.")
            }
            Section("Freigabe") {Text("Eine öffentliche Distribution erfolgt erst nach Build-, Geräte- und Funktionsabnahme. Eine spätere App-Store-Zulassung ist nicht zugesagt.")}
        }.navigationTitle("Version & Installation")
    }
}
struct BundledTextScreen:View {
    let name:String
    var extensionName:String?=nil
    let title:String
    var body:some View {
        ScrollView {
            Text(content).font(.footnote).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).padding(16)
        }.navigationTitle(title)
    }
    private var content:String {
        guard let url=Bundle.main.url(forResource:name,withExtension:extensionName),let text=try? String(contentsOf:url,encoding:.utf8) else{return "Das Dokument fehlt im App-Bundle. Die vollständigen Hinweise liegen im Quellcode bei."}
        return text
    }
}

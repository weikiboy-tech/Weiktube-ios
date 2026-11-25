// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct DiagnosticsScreen:View {
    @ObservedObject private var store=DiagnosticsStore.shared
    @ObservedObject var home: WebSession
    @ObservedObject var network: NetworkMonitor
    var body:some View {
        List {
            Section("YouTube-Startseite") {
                LabeledContent("Netzwerk", value: network.connected ? "Verbunden" : "Keine bestätigte Verbindung")
                LabeledContent("Website", value: home.currentURL?.host ?? "Noch nicht geöffnet")
                LabeledContent("Ladezustand", value: home.loading ? "Lädt" : home.errorMessage != nil ? "Fehler" : home.currentURL == nil ? "Nicht geladen" : "Geladen")
                Text("Videolinks öffnen den Weiktube-Player. Google-Freigaben für Abos und Playlists verwaltest du unter „Du“. Anmeldedaten und AutoFill verwaltet iOS.")
                    .font(.footnote)
                if let error = home.errorMessage { Text(error) }
                Button("Website erneut laden") { home.reload() }.disabled(home.currentURL == nil)
                Link("YouTube im Standardbrowser vergleichen", destination: URL(string: "https://m.youtube.com/")!)
            }
            Section {Text("Lokaler Ereignispuffer, maximal 200 Einträge. Kein automatischer Versand; keine Konto-, Cookie-, URL- oder Videodaten.").font(.footnote).foregroundStyle(.secondary)}
            Section {
                ShareLink(item:store.report){Label("Diagnosebericht teilen",systemImage:"square.and.arrow.up")}
                Button("Ereignisse leeren",role:.destructive){store.clear()}
            }
            ForEach(store.entries.reversed()){entry in
                VStack(alignment:.leading){Text(entry.event.rawValue).font(.footnote.monospaced());if let detail = entry.detail { Text(detail).font(.caption.monospaced()) };Text(entry.date,style:.time).font(.caption).foregroundStyle(.secondary)}
            }
        }.navigationTitle("Diagnose")
    }
}

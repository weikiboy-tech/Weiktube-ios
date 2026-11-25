// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct DiagnosticsScreen:View {
    @ObservedObject private var store=DiagnosticsStore.shared
    var body:some View {
        List {
            Section {Text("Lokaler Ereignispuffer, maximal 200 Einträge. Kein automatischer Versand; keine Konto-, Cookie-, URL- oder Videodaten.").font(.footnote).foregroundStyle(.secondary)}
            Section {
                ShareLink(item:store.report){Label("Diagnosebericht teilen",systemImage:"square.and.arrow.up")}
                Button("Ereignisse leeren",role:.destructive){store.clear()}
            }
            ForEach(store.entries.reversed()){entry in
                VStack(alignment:.leading){Text(entry.event.rawValue).font(.footnote.monospaced());Text(entry.date,style:.time).font(.caption).foregroundStyle(.secondary)}
            }
        }.navigationTitle("Diagnose")
    }
}

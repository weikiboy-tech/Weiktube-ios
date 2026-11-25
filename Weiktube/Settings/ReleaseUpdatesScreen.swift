// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

@MainActor
struct ReleaseUpdatesScreen:View {
    @ObservedObject var checker:ReleaseChecker
    @ObservedObject var settings:AppSettings

    var body:some View {
        List {
            Section("Installierte Version") {
                LabeledContent("Weiktube",value:checker.installedVersion)
            }
            Section("Offizielle Release-Informationen") {
                status
                if let attempt=checker.lastAttempt {
                    HStack {Text("Letzter Versuch");Spacer();Text(attempt,format:.dateTime.day().month().year().hour().minute()).foregroundStyle(.secondary)}
                        .font(.footnote)
                }
                if let checked=checker.lastChecked {
                    HStack {Text("Zuletzt bestätigt");Spacer();Text(checked,format:.dateTime.day().month().year().hour().minute()).foregroundStyle(.secondary)}
                        .font(.footnote)
                }
                Button {Task {await checker.check()}} label:{Label("Jetzt nach Release suchen",systemImage:"arrow.clockwise")}
                    .disabled(checker.isChecking)
            }
            Section {
                Toggle("Release-Informationen täglich prüfen",isOn:$settings.automaticUpdateChecks)
                Text("Nach deiner Aktivierung wird höchstens einmal täglich die öffentliche GitHub-Release-Adresse geprüft. Dabei werden keine Google-Tokens oder Repository-Anmeldedaten gesendet.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let release=checker.release,release.isValid {
                Section("Bestätigtes Release") {
                    LabeledContent("Version",value:release.tag)
                    Text(release.name).font(.headline)
                    Text(release.publishedAt,format:.dateTime.day().month().year()).font(.subheadline).foregroundStyle(.secondary)
                    if !release.notes.isEmpty {Text(release.notes).font(.subheadline).textSelection(.enabled)}
                    Link("Release auf GitHub öffnen",destination:release.htmlURL)
                    if checker.state != .current && checker.state != .updateAvailable && checker.state != .ahead && checker.state != .installedVersionUnknown {
                        Text("Dies ist der zuletzt bestätigte, gespeicherte Stand. Die aktuelle Verfügbarkeit ist noch nicht bestätigt.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Installation") {
                Text("Die Prüfung zeigt Versionsinformationen. Neue signierte Builds werden über den eingerichteten Xcode-, TestFlight- oder App-Store-Weg installiert.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("App-Updates").tint(.weiktubeAccent)
        .onChange(of:settings.automaticUpdateChecks) {_,enabled in
            if enabled {Task {await checker.check(automatically:true)}}
        }
    }

    @ViewBuilder private var status:some View {
        switch checker.state {
        case .idle:
            Text("Noch keine öffentliche Release-Prüfung durchgeführt.").foregroundStyle(.secondary)
        case .cached:
            Label("Gespeicherte Release-Informationen",systemImage:"clock")
        case .checking:
            ProgressView("GitHub-Release wird geprüft …")
        case .updateAvailable:
            Label("Eine neuere veröffentlichte Version ist verfügbar.",systemImage:"arrow.up.circle").foregroundStyle(Color.weiktubeAccent)
        case .current:
            Label("Die installierte Version entspricht dem bestätigten Release.",systemImage:"checkmark.circle")
        case .ahead:
            Label("Dieser Build ist neuer als das bestätigte öffentliche Release.",systemImage:"hammer")
        case .installedVersionUnknown:
            Text("Ein Release wurde bestätigt. Die Versionsnummer dieses Builds kann nicht automatisch verglichen werden.")
        case .privateOrUnavailable:
            Label("Kein öffentlich abrufbares Release. Das Repository kann privat sein oder noch kein veröffentlichtes Release enthalten.",systemImage:"lock.rectangle")
        case .failed(let message):
            Label(message,systemImage:"exclamationmark.circle").foregroundStyle(.orange)
        }
    }
}

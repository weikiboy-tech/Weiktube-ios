// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct AdBlockScreen: View {
    @ObservedObject var service: AdBlockService
    var onReloadPages: () -> Void = {}
    @State private var editingDomains = false
    @State private var custom = ""
    @State private var exceptions = ""
    @State private var validationError: String?
    @State private var saving = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Image(systemName: service.enabled ? "shield.lefthalf.filled" : "shield.slash")
                        .font(.system(size: 34)).foregroundStyle(.mint).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Weiktube Shield").font(.title2.bold())
                        Text(service.status).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                VStack(spacing: 14) {
                    Toggle("Werbeschutz", isOn: Binding(get: { service.enabled }, set: { value in Task { await service.setEnabled(value) } }))
                        .accessibilityIdentifier("adblockEnabled")
                    Divider()
                    Toggle("Werbedomains und YouTube-Filter", isOn: preference(\.ads))
                    Toggle("Tracking-Domains blockieren", isOn: preference(\.trackers))
                }.padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
                if service.requiresReload {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Neue Dokumente verwenden die geänderten Filter. Bereits installierte Scriptlets werden erst beim Neuladen vollständig ersetzt.").font(.footnote)
                        Button("Offene Seiten neu laden") { onReloadPages(); service.didReloadPages() }
                            .buttonStyle(.bordered)
                    }.padding().background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Filterstatus").font(.headline)
                    LabeledContent("Regelsatz", value: "Version \(service.version)")
                    LabeledContent("Kompilierte Regeln", value: service.ruleCount.formatted())
                    if let date = service.lastUpdate { LabeledContent("Zuletzt geprüft", value: date.formatted(date: .abbreviated, time: .shortened)) }
                    Button {
                        Task { await service.checkForUpdates() }
                    } label: {
                        if service.isUpdating { ProgressView().frame(maxWidth: .infinity) }
                        else { Label("Signiertes Filterupdate prüfen", systemImage: "arrow.clockwise") }
                    }.disabled(service.isUpdating)
                    Button("Eigene Domains und Ausnahmen") {
                        custom = service.preferences.customDomains.sorted().joined(separator: "\n")
                        exceptions = service.preferences.exceptions.sorted().joined(separator: "\n")
                        validationError = nil; editingDomains = true
                    }
                }.padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 12) {
                    Text("Diagnose dieser Sitzung").font(.headline)
                    LabeledContent("Entfernte Datenfelder", value: service.dataRemoved.formatted())
                    LabeledContent("Ausgeblendete Werbeelemente", value: service.cosmeticHidden.formatted())
                    LabeledContent("Erkannte Werbedurchbrüche", value: service.breakthroughs.formatted())
                    LabeledContent("Scriptlet-Fehler", value: service.scriptErrors.formatted())
                    Text("Seitenmeldungen erfassen beobachtete Änderungen. WebKit stellt keine Anzahl blockierter Netzwerkanfragen bereit. Diese Zahlen belegen keine vollständige Werbefreiheit.").font(.footnote).foregroundStyle(.secondary)
                    Button("Zähler zurücksetzen") { service.resetCounters() }
                    NavigationLink("Lokalen WebKit-Filtertest öffnen") { ShieldSelfTestScreen() }
                    NavigationLink("Geschützten Browser öffnen") { ShieldBrowserScreen(adBlock:service) }
                }.padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 10) {
                    Text("Datenschutz und Quellen").font(.headline)
                    Text("Filter laufen lokal mit WebKit. Updates enthalten ausschließlich signierte, eingeschränkte Regeldaten. Kein VPN und keine zusätzliche Telemetrie.").font(.footnote).foregroundStyle(.secondary)
                    Link("Filterquellen und Lizenz", destination: URL(string: "https://github.com/weikiboy-tech/Weiktube/blob/a7e0a9221e73d3d9c361f614adcb9e027fb70c35/content-filter/src/main/assets/weiktube-adblock/PROVENANCE.md")!)
                    Text("AdGuard Scriptlets 2.5.1 © Adguard Software Ltd. und Mitwirkende · GPL-3.0. Anpassungen aus Weiktube Android.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(16)
        }
        .navigationTitle("Adblock")
        .tint(Color(red: 0.396, green: 0.847, blue: 0.784))
        .sheet(isPresented: $editingDomains) { domainEditor }
    }
    private func preference(_ keyPath: WritableKeyPath<AdBlockPreferences, Bool>) -> Binding<Bool> {
        Binding(get: { service.preferences[keyPath: keyPath] }, set: { value in
            var changed = service.preferences; changed[keyPath: keyPath] = value
            Task { await service.setPreferences(changed) }
        })
    }
    private var domainEditor: some View {
        NavigationStack {
            Form {
                Section("Zusätzlich blockierte Domains") {
                    TextEditor(text: $custom).font(.system(.body, design: .monospaced)).frame(minHeight: 130)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("Blockierte Domains")
                }
                Section("Ausnahmen") {
                    TextEditor(text: $exceptions).font(.system(.body, design: .monospaced)).frame(minHeight: 130)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("Ausgenommene Domains")
                }
                Text("Eine Domain pro Zeile oder Hosts-Format. Unterdomains werden eingeschlossen. EasyList-Syntax wird nicht unterstützt. Medien-, Untertitel- und Anmeldedomains werden nicht pauschal gesperrt.").font(.footnote)
                if let validationError { Text(validationError).foregroundStyle(.red).accessibilityIdentifier("domainValidationError") }
            }
            .navigationTitle("Filterlisten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { editingDomains = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        saving = true
                        Task {
                            do { try await service.setDomainLists(custom: custom, exceptions: exceptions); editingDomains = false }
                            catch { validationError = "Ungültige Liste. Bitte ausschließlich Domains oder Hosts-Einträge verwenden (höchstens 256 KiB / 4096 Domains)." }
                            saving = false
                        }
                    }.disabled(saving)
                }
            }
        }
    }
}

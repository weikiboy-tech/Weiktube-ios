// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

extension SponsorCategory {
    var color: Color { Color(red: Double((colorHex >> 16) & 255) / 255, green: Double((colorHex >> 8) & 255) / 255, blue: Double(colorHex & 255) / 255) }
}

struct SponsorBlockSettingsScreen: View {
    @ObservedObject var service: SponsorBlockService
    var body: some View {
        Form {
            Section {
                Toggle("SponsorBlock aktivieren", isOn: $service.settings.enabled)
                Text("Beim Öffnen eines Videos werden die ersten vier Zeichen des SHA-256-Hashes an SponsorBlock gesendet. Community-Daten können unvollständig oder fehlerhaft sein.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text(service.status).font(.footnote).accessibilityIdentifier("sponsorStatus")
            }
            Section("Kategorien") {
                ForEach(SponsorCategory.allCases) { category in
                    Picker(selection: Binding(get: { service.settings.mode(for: category) }, set: { service.settings.modes[category.rawValue] = $0 })) {
                        ForEach(SponsorMode.allCases) { mode in Text(mode.title).tag(mode) }
                    } label: {
                        Label { Text(category.title) } icon: { Circle().fill(category.color).frame(width: 12, height: 12).accessibilityHidden(true) }
                    }
                }
            }
            Section("Darstellung") {
                Toggle("Farbige Zeitmarkierungen", isOn: $service.settings.markers)
                Toggle("Überspring-Hinweise und Rückgängig", isOn: $service.settings.notices)
                Toggle("Statistiken anzeigen", isOn: $service.settings.showStatistics)
            }
            if service.settings.showStatistics {
                Section("Lokal gespeichert") {
                    LabeledContent("Übersprungene Abschnitte", value: service.statistics.count.formatted())
                    LabeledContent("Gesparte Zeit", value: Duration.seconds(service.statistics.seconds).formatted(.time(pattern: .hourMinuteSecond)))
                    Button("Statistiken zurücksetzen", role: .destructive) { service.resetStatistics() }
                }
            }
            Section {
                Button("Segment-Cache leeren") { Task { await service.clearCache() } }
                Link("SponsorBlock und Datenschutz", destination: URL(string: "https://wiki.sponsor.ajay.app/w/SponsorBlock%3APrivacy_policy")!)
                Link("Community-Daten: CC BY-NC-SA 4.0", destination: URL(string: "https://creativecommons.org/licenses/by-nc-sa/4.0/")!)
                Text("Daten von SponsorBlock. Keine Google-Zugangsdaten, Cookies oder Bewertungen werden an den Dienst übermittelt.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("SponsorBlock")
        .tint(Color(red: 0.396, green: 0.847, blue: 0.784))
    }
}

struct SponsorMarkersView: View {
    let segments: [SponsorSegment]
    let duration: Double
    let settings: SponsorSettings
    var body: some View {
        GeometryReader { geometry in
            if settings.enabled && settings.markers && duration.isFinite && duration > 0 {
                ForEach(segments.filter { $0.valid(for: duration) && settings.mode(for: $0.category) != .off }) { segment in
                    Rectangle().fill(segment.category.color)
                        .frame(width: max(1, geometry.size.width * (min(duration, segment.end) - segment.start) / duration))
                        .offset(x: geometry.size.width * segment.start / duration)
                }
            }
        }
        .frame(height: 3).clipped().allowsHitTesting(false).accessibilityHidden(true)
    }
}

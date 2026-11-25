// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct ReturnDislikeSettingsScreen: View {
    @ObservedObject var service: ReturnDislikeService
    var body: some View {
        Form {
            Section {
                Toggle("Dislike-Schätzungen anzeigen", isOn: $service.enabled)
                Text("Mit dieser Option wird die öffentliche Video-ID an Return YouTube Dislike gesendet. Die angezeigten Zahlen sind Schätzungen und keine offiziellen YouTube-Zahlen.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text(service.status).font(.footnote)
            }
            Section {
                Button("Cache leeren") { Task { await service.clearCache() } }
                Link("Return YouTube Dislike", destination: URL(string: "https://returnyoutubedislike.com/")!)
                Text("Keine Google-Zugangsdaten, Cookies oder Abstimmungen werden übertragen. Fehler und Rate-Limits beeinträchtigen die Videowiedergabe nicht.").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Dislikes")
    }
}

struct ReturnDislikeBadge: View {
    @ObservedObject var service: ReturnDislikeService
    var body: some View {
        if service.enabled, let count = service.count {
            Label("≈ \(count.formatted())", systemImage: "hand.thumbsdown")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityLabel("Etwa \(count.formatted()) Dislikes. Schätzung von Return YouTube Dislike.")
        }
    }
}

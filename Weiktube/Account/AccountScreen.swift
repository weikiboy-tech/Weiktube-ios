// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

enum AccountPalette {
    static let background = Color.weiktubeBackground
    static let card = Color.weiktubeCard
    static let mint = Color.weiktubeAccent
}

@MainActor
struct AccountScreen: View {
    @ObservedObject var store: AccountStore
    let onOpenVideo: (String) -> Void
    @State private var confirmDisconnect = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        AccountThumbnail(url: store.channel?.thumbnailURL, symbol: "person.crop.circle.fill", width: 56, height: 56)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.channel?.title ?? "Dein Weiktube").font(.title2.bold())
                            Text(store.isSignedIn ? "YouTube-Konto verbunden" : "Deine Videos. Dein Konto.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 8)
                }.listRowBackground(AccountPalette.card)

                if store.isSignedIn {
                    Section("Dein YouTube") {
                        NavigationLink {
                            SubscriptionsScreen(store: store, onOpenVideo: onOpenVideo)
                        } label: { Label("Abonnements", systemImage: "play.rectangle.on.rectangle") }
                        NavigationLink {
                            PlaylistsScreen(store: store, onOpenVideo: onOpenVideo)
                        } label: { Label("Playlists", systemImage: "text.badge.plus") }
                    }.listRowBackground(AccountPalette.card)
                    if !store.channels.isEmpty {
                        Section("Deine YouTube-Kanäle") {
                            ForEach(store.channels) {channel in
                                Link(destination:URL(string:"https://www.youtube.com/channel/\(channel.id)")!) {
                                    HStack(spacing:12) {
                                        AccountThumbnail(url:channel.thumbnailURL,symbol:"person.crop.circle.fill",width:40,height:40).clipShape(Circle())
                                        Text(channel.title).foregroundStyle(.primary)
                                        Spacer()
                                        Image(systemName:"arrow.up.right.square")
                                    }
                                }.accessibilityLabel("\(channel.title), Kanal in YouTube öffnen")
                            }
                        }.listRowBackground(AccountPalette.card)
                    }
                }

                Section("Google-Freigabe") {
                    if let issue = store.configurationIssue {
                        Label(issue, systemImage: "wrench.and.screwdriver")
                            .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    } else if !store.isSignedIn {
                        Button { Task { await store.signIn() } } label: {
                            Label("Mit Google verbinden", systemImage: "person.crop.circle.badge.checkmark")
                        }.disabled(store.isAuthenticating || store.hasPendingRevocation)
                    } else {
                        Button("Konto wechseln") { Task { await store.signIn() } }.disabled(store.isAuthenticating)
                        if !store.hasInteractionPermission {
                            Button("Interaktionen mit Google freigeben") { Task { await store.authorizeInteractions() } }
                                .disabled(store.isAuthenticating)
                            Text("Zusätzliche Freigabe für Bewertungen, Abos, Kommentare und das Speichern in Playlists. Jede Änderung erfolgt erst über eine eigene Aktionsschaltfläche.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Button("Lokal abmelden", role: .destructive) { Task { await store.signOut() } }
                        Button("Google-Zugriff widerrufen", role: .destructive) { confirmDisconnect = true }
                            .disabled(store.isAuthenticating)
                    }
                    if store.isAuthenticating || store.accountLoading { ProgressView("Google-Verbindung wird vorbereitet …") }
                    Text(store.status).font(.footnote).foregroundStyle(.secondary)
                    AccountErrorRow(message: store.errorMessage)
                    AccountPendingRevocationControls(store:store)
                }.listRowBackground(AccountPalette.card)

                Section("Anmeldung und Datenschutz") {
                    Text("Diese Freigabe verbindet die nativen Kontoansichten mit der offiziellen YouTube Data API. Sie meldet die originale YouTube-Webseite in der App nicht automatisch an.")
                    Text("Google-Passwörter werden ausschließlich im Systemdialog eingegeben. Tokens bleiben im Schlüsselbund und werden weder an WebViews noch an SponsorBlock oder Return YouTube Dislike weitergegeben.")
                    Text("YouTube stellt „Später ansehen“ und den YouTube-Verlauf nicht über die Data API bereit. Der lokale Weiktube-Verlauf ist davon unabhängig.")
                    Link("Google-Verbindungen verwalten", destination: URL(string: "https://myaccount.google.com/connections")!)
                }.font(.footnote).foregroundStyle(.secondary).listRowBackground(AccountPalette.card)
            }
            .scrollContentBackground(.hidden).background(AccountPalette.background)
            .tint(AccountPalette.mint).navigationTitle("Du")
            .task(id: "\(store.sessionRevision)-\(store.isSignedIn)") { await store.loadIfNeeded() }
            .refreshable { await store.refreshAccount() }
            .confirmationDialog("Google-Zugriff widerrufen?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
                Button("Zugriff widerrufen", role: .destructive) { Task { await store.disconnect() } }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Die lokale Sitzung wird gelöscht und Weiktubes Google-Freigabe widerrufen. Dein Google-Konto bleibt bestehen.")
            }
        }
    }
}

@MainActor
struct AccountConnectionPrompt: View {
    @ObservedObject var store: AccountStore
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.checkmark").font(.system(size: 40)).foregroundStyle(AccountPalette.mint)
            Text("Mit deinem YouTube verbinden").font(.headline)
            Text(store.configurationIssue ?? "Google-Freigabe für deine Abos und Playlists. Die YouTube-Webseite verwendet eine eigene Sitzung.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if store.configurationIssue == nil {
                Button("Mit Google verbinden") { Task { await store.signIn() } }
                    .buttonStyle(.borderedProminent).tint(AccountPalette.mint).foregroundStyle(.black)
                    .disabled(store.isAuthenticating || store.hasPendingRevocation)
            }
            if store.isAuthenticating { ProgressView() }
            AccountErrorRow(message: store.errorMessage)
            AccountPendingRevocationControls(store:store)
        }.padding(24)
    }
}

@MainActor
private struct AccountPendingRevocationControls:View {
    @ObservedObject var store:AccountStore
    @State private var discard=false
    var body:some View {
        Group {
            if store.hasPendingRevocation {
                Text("Ausstehender Google-Widerruf. Die Wiederholungsdaten liegen geschützt im Schlüsselbund. Es gibt keine automatischen Versuche.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Höchstens fünf ausdrückliche Versuche innerhalb von sieben Tagen; danach bleibt die Verwaltung direkt bei Google möglich.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Widerruf erneut versuchen (\(store.revocationAttemptsRemaining) übrig)") {Task {await store.retryRevocation()}}
                    .disabled(!store.canRetryRevocation)
                Link("Freigabe direkt bei Google prüfen",destination:URL(string:"https://myaccount.google.com/connections")!)
                Button("Lokale Wiederholungsdaten verwerfen",role:.destructive) {discard=true}.disabled(store.isAuthenticating)
            }
        }.confirmationDialog("Wiederholungsdaten verwerfen?",isPresented:$discard,titleVisibility:.visible) {
            Button("Wiederholungsdaten löschen",role:.destructive) {store.discardRevocationRetry()}
            Button("Abbrechen",role:.cancel) {}
        } message:{Text("Google kann weiterhin eine Freigabe besitzen. Prüfe sie gegebenenfalls unter myaccount.google.com/connections. Ohne die lokalen Daten kann Weiktube diesen Widerruf nicht erneut senden.")}
    }
}

struct AccountErrorRow: View {
    let message: String?
    var body: some View {
        if let message, !message.isEmpty {
            Label(message, systemImage: "exclamationmark.circle")
                .font(.footnote).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Hinweis: \(message)")
        }
    }
}

@MainActor
struct AccountThumbnail: View {
    let url: URL?
    let symbol: String
    let width: CGFloat
    let height: CGFloat
    @State private var image:Image?
    @State private var visible=false
    var body: some View {
        ZStack {
            if let image { image.resizable().scaledToFill() }
            else { Rectangle().fill(AccountPalette.card).overlay(Image(systemName: symbol).foregroundStyle(AccountPalette.mint)) }
        }.frame(width: width, height: height).clipped().accessibilityHidden(true)
            .task(id:url) {
                visible=true
                image=nil
                guard let url,let bitmap=await AccountThumbnailLoader.shared.load(url),!Task.isCancelled,visible else{return}
                image=Image(decorative:bitmap.image,scale:1,orientation:.up)
            }
            .onDisappear {visible=false;image=nil}
    }
}

struct AccountVideoRow: View {
    let video: YouTubeVideo
    let onOpenVideo: (String) -> Void
    var body: some View {
        Button { onOpenVideo(video.id) } label: {
            HStack(alignment: .top, spacing: 12) {
                AccountThumbnail(url: video.thumbnailURL, symbol: "play.rectangle", width: 120, height: 68).clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 5) {
                    Text(video.title).font(.subheadline.weight(.semibold)).lineLimit(3).foregroundStyle(.primary)
                    Text(video.channelTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let date = video.publishedAt { Text(date, style: .date).font(.caption2).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
            }.padding(.vertical, 4)
        }.buttonStyle(.plain).accessibilityLabel("\(video.title), \(video.channelTitle), abspielen")
    }
}

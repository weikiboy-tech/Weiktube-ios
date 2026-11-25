// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

@MainActor
struct SubscriptionsScreen: View {
    @ObservedObject var store: AccountStore
    let onOpenVideo: (String) -> Void
    @State private var selectedSection = 0
    @StateObject private var lease=AccountScreenLease()

    var body: some View {
        NavigationStack {
            Group {
                if !store.isSignedIn {
                    AccountConnectionPrompt(store: store)
                } else {
                    List {
                        Picker("Ansicht", selection: $selectedSection) {
                            Text("Neue Videos").tag(0)
                            Text("Kanäle").tag(1)
                        }.pickerStyle(.segmented).listRowBackground(Color.clear)
                        if selectedSection == 0 {
                            Section {
                                ForEach(store.feedVideos) { video in AccountVideoRow(video: video, onOpenVideo: onOpenVideo) }
                                if store.feedLoading { ProgressView("Neue Videos werden geladen …") }
                                if !store.feedLoading && store.feedVideos.isEmpty {
                                    Text("Für die geladenen Abos sind noch keine verfügbaren Uploads vorhanden.")
                                        .foregroundStyle(.secondary)
                                }
                                if store.hasMoreFeedChannels {
                                    Button("Weitere abonnierte Kanäle laden") {lease.start {await store.loadFeed(reset:false)}}
                                        .disabled(store.feedLoading)
                                }
                            } footer: {
                                Text("Jeweils drei aktuelle Uploads aus \(store.loadedFeedChannels) geladenen Kanälen, nach Veröffentlichungsdatum sortiert.")
                            }.listRowBackground(AccountPalette.card)
                            AccountErrorRow(message: store.feedMessage).listRowBackground(AccountPalette.card)
                        } else {
                            Section {
                                ForEach(store.subscriptions) { subscription in
                                    NavigationLink {
                                        SubscriptionChannelScreen(store: store, subscription: subscription, onOpenVideo: onOpenVideo)
                                    } label: {
                                        HStack(spacing: 12) {
                                            AccountThumbnail(url: subscription.thumbnailURL, symbol: "person.crop.circle", width: 40, height: 40).clipShape(Circle())
                                            Text(subscription.title)
                                        }
                                    }
                                }
                                if store.hasMoreSubscriptions {
                                    Button("Weitere Abos laden") {lease.start {await store.loadMoreSubscriptions()}}
                                        .disabled(store.subscriptionsLoading)
                                }
                                if store.subscriptionsLoading || store.accountLoading { ProgressView() }
                                if store.subscriptions.isEmpty && !store.accountLoading { Text("Keine Abonnements vorhanden.").foregroundStyle(.secondary) }
                            }.listRowBackground(AccountPalette.card)
                        }
                        AccountErrorRow(message: store.errorMessage).listRowBackground(AccountPalette.card)
                    }
                    .scrollContentBackground(.hidden)
                    .refreshable {
                        await lease.perform {
                            if selectedSection == 0 { await store.loadFeed(reset: true) }
                            else { await store.refreshAccount() }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(AccountPalette.background)
            .tint(AccountPalette.mint).navigationTitle("Abos")
            .task(id: "\(store.sessionRevision)-\(store.isSignedIn)") {
                await store.loadIfNeeded()
                await lease.perform {await store.loadFeedIfNeeded()}
            }
            .onChange(of:selectedSection) {_,_ in lease.cancel()}
            .onDisappear {lease.cancel()}
        }
    }
}

@MainActor
private struct SubscriptionChannelScreen: View {
    @ObservedObject var store: AccountStore
    let subscription: YouTubeSubscription
    let onOpenVideo: (String) -> Void
    @State private var videos: [YouTubeVideo] = []
    @State private var message: String?
    @State private var busy = false
    @State private var requestID = UUID()
    @StateObject private var lease=AccountScreenLease()

    var body: some View {
        List {
            Section {
                ForEach(videos) { video in AccountVideoRow(video: video, onOpenVideo: onOpenVideo) }
                if busy { ProgressView("Uploads werden geladen …") }
                if !busy && videos.isEmpty { Text("Keine aktuellen Uploads verfügbar.").foregroundStyle(.secondary) }
                AccountErrorRow(message: message)
            }.listRowBackground(AccountPalette.card)
            if let url = URL(string: "https://www.youtube.com/channel/\(subscription.channelID)") {
                Link("Kanal in YouTube öffnen", destination: url).listRowBackground(AccountPalette.card)
            }
        }
        .scrollContentBackground(.hidden).background(AccountPalette.background)
        .navigationTitle(subscription.title).navigationBarTitleDisplayMode(.inline)
        .task(id: "\(store.sessionRevision)-\(store.isSignedIn)") {await lease.perform {await load()}}
        .refreshable {await lease.perform {await load()}}
        .onDisappear {lease.cancel();requestID = UUID(); busy = false}
    }

    private func load() async {
        let identifier = UUID()
        requestID = identifier
        let revision = store.sessionRevision
        busy = true; videos = []; message = nil
        defer { if requestID == identifier { busy = false } }
        do {
            try store.checkSession(revision)
            guard store.subscriptions.contains(where: { $0.channelID == subscription.channelID }) else { throw AccountError.sessionChanged }
            let result = try await store.api.recentUploads(channelIDs: [subscription.channelID], expected: revision)
            try store.checkSession(revision)
            guard requestID == identifier else { return }
            videos = result.videos
        } catch { if revision == store.sessionRevision && requestID == identifier { message = error.localizedDescription } }
    }
}

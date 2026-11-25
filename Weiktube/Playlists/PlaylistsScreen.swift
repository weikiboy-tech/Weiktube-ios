// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

@MainActor
struct PlaylistsScreen: View {
    @ObservedObject var store: AccountStore
    let onOpenVideo: (String) -> Void
    @StateObject private var lease=AccountScreenLease()

    var body: some View {
        Group {
            if !store.isSignedIn {
                AccountConnectionPrompt(store: store)
            } else {
                List {
                    Section {
                        ForEach(store.playlists) { playlist in
                            NavigationLink {
                                PlaylistItemsScreen(store: store, playlist: playlist, onOpenVideo: onOpenVideo)
                            } label: {
                                HStack(spacing: 12) {
                                    AccountThumbnail(url: playlist.thumbnailURL, symbol: "text.badge.plus", width: 96, height: 54)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(playlist.title).font(.headline)
                                        Text("\(playlist.itemCount) Videos").font(.caption).foregroundStyle(.secondary)
                                    }
                                }.padding(.vertical, 4)
                            }
                        }
                        if store.hasMorePlaylists {
                            Button("Weitere Playlists laden") {lease.start {await store.loadMorePlaylists()}}
                                .disabled(store.playlistsLoading)
                        }
                        if store.playlistsLoading || store.accountLoading { ProgressView() }
                        if store.playlists.isEmpty && !store.accountLoading { Text("Keine eigenen Playlists vorhanden.").foregroundStyle(.secondary) }
                        AccountErrorRow(message: store.errorMessage)
                    } footer: {
                        Text("Eigene YouTube-Playlists. „Später ansehen“ und der YouTube-Verlauf sind über die offizielle API nicht verfügbar.")
                    }.listRowBackground(AccountPalette.card)
                }.scrollContentBackground(.hidden).refreshable {await lease.perform {await store.refreshAccount()}}
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(AccountPalette.background)
        .navigationTitle("Playlists").tint(AccountPalette.mint)
        .task(id: "\(store.sessionRevision)-\(store.isSignedIn)") { await store.loadIfNeeded() }
        .onDisappear {lease.cancel()}
    }
}

@MainActor
private struct PlaylistItemsScreen: View {
    @ObservedObject var store: AccountStore
    let playlist: YouTubePlaylist
    let onOpenVideo: (String) -> Void
    @State private var items: [YouTubePlaylistEntry] = []
    @State private var nextToken: String?
    @State private var busy = false
    @State private var message: String?
    @State private var requestID = UUID()
    @StateObject private var lease=AccountScreenLease()

    var body: some View {
        List {
            Section {
                ForEach(items) { item in AccountVideoRow(video: item.video, onOpenVideo: onOpenVideo) }
                if busy { ProgressView("Playlist wird geladen …") }
                if !busy && items.isEmpty { Text("Keine verfügbaren Videos in dieser Playlist.").foregroundStyle(.secondary) }
                if nextToken != nil {
                    Button("Weitere Videos laden") {lease.start {await load(reset:false)}}.disabled(busy)
                }
                AccountErrorRow(message: message)
            }.listRowBackground(AccountPalette.card)
        }
        .scrollContentBackground(.hidden).background(AccountPalette.background)
        .navigationTitle(playlist.title).navigationBarTitleDisplayMode(.inline)
        .task(id: store.sessionRevision) {await lease.perform {await load(reset:true)}}
        .refreshable {await lease.perform {await load(reset:true)}}
        .onDisappear {lease.cancel();requestID = UUID(); busy = false}
    }

    private func load(reset: Bool) async {
        if reset { requestID = UUID(); busy = false; items = []; nextToken = nil }
        guard !busy, reset || nextToken != nil else { return }
        let request = UUID()
        requestID = request
        let revision = store.sessionRevision
        let token = reset ? nil : nextToken
        busy = true; message = nil
        defer { if request == requestID { busy = false } }
        do {
            try store.checkSession(revision)
            // A stale navigation destination must not show another account's private playlist.
            guard store.playlists.contains(where: { $0.id == playlist.id }) else { throw AccountError.sessionChanged }
            let response = try await store.api.playlistItems(playlistID: playlist.id, token: token, expected: revision)
            try store.checkSession(revision)
            guard request == requestID else { return }
            var seen: Set<String> = []
            items = ((reset ? [] : items) + response.items).filter { seen.insert($0.id).inserted }
            nextToken = response.nextPageToken
        } catch { if revision == store.sessionRevision && request == requestID { message = error.localizedDescription } }
    }
}

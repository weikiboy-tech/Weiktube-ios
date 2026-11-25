// SPDX-License-Identifier: GPL-3.0-only
import Combine
import SwiftUI

@MainActor
final class VideoActionsModel: ObservableObject {
    @Published private(set) var video: YouTubeVideo?
    @Published private(set) var rating: YouTubeRating?
    @Published private(set) var subscriptionID: String?
    @Published private(set) var subscriptionKnown = false
    @Published private(set) var comments: [YouTubeComment] = []
    @Published private(set) var replies: [String: [YouTubeComment]] = [:]
    @Published private(set) var hasMoreComments = false
    @Published private(set) var moreReplies: Set<String> = []
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    @Published private(set) var commentsMessage: String?
    @Published private(set) var postedSequence = 0
    private let store: AccountStore
    private let videoID: String
    private var loadedRevision: UInt64?
    private var requestID = UUID()
    private var nextComments: String?
    private var nextReplies: [String: String] = [:]
    private var repliesLoaded: Set<String> = []
    private var work: Task<Void, Never>?

    init(store: AccountStore, videoID: String) {
        self.store = store
        self.videoID = videoID
    }

    func load() async {
        close()
        video = nil; rating = nil; subscriptionID = nil; subscriptionKnown = false
        comments = []; replies = [:]; nextComments = nil; nextReplies = [:]
        repliesLoaded = []; moreReplies = []; hasMoreComments = false; commentsMessage = nil; message = nil
        guard store.isSignedIn else { return }
        let identifier = UUID()
        requestID = identifier
        let revision = store.sessionRevision
        loadedRevision = revision
        busy = true
        defer { if requestID == identifier { busy = false } }
        do {
            let detail = try await store.api.video(videoID, expected: revision)
            try ensure(identifier, revision)
            video = detail
            do {
                let value = try await store.api.rating(videoID: videoID, expected: revision)
                try ensure(identifier, revision)
                rating = value
            } catch {
                try ensure(identifier, revision)
                message = error.localizedDescription
                store.handle(error, expected: revision)
            }
            do {
                let value = try await store.api.subscriptionID(channelID: detail.channelID, expected: revision)
                try ensure(identifier, revision)
                subscriptionID = value; subscriptionKnown = true
            } catch {
                try ensure(identifier, revision)
                message = error.localizedDescription
                store.handle(error, expected: revision)
            }
            if store.hasInteractionPermission {
                do {
                    let page = try await store.api.comments(videoID: videoID, expected: revision)
                    try ensure(identifier, revision)
                    comments = page.items
                    nextComments = page.nextPageToken
                    hasMoreComments = nextComments != nil
                } catch {
                    try ensure(identifier, revision)
                    commentsMessage = error.localizedDescription
                    store.handle(error, expected: revision)
                }
            } else {
                commentsMessage = "Kommentare und Interaktionen benötigen die zusätzliche Google-Freigabe. Die Freigabe selbst veröffentlicht nichts."
            }
        } catch {
            guard requestID == identifier, revision == store.sessionRevision, !(error is CancellationError) else { return }
            message = error.localizedDescription
            store.handle(error, expected: revision)
        }
    }

    func setRating(_ target: YouTubeRating) {
        guard rating != nil else { return }
        perform(write: true) { [self] revision in
            try await store.api.rate(videoID: videoID, rating: target, expected: revision)
            try store.checkSession(revision)
            rating = target
            return target == .none ? "Deine Bewertung wurde entfernt." : "Deine Bewertung wurde von YouTube bestätigt."
        }
    }

    func toggleSubscription() {
        guard subscriptionKnown, let channel = video?.channelID else { return }
        let wanted = subscriptionID == nil
        perform(write: true) { [self] revision in
            let id = try await store.api.setSubscribed(wanted, channelID: channel, expected: revision)
            try store.checkSession(revision)
            subscriptionID = id
            return wanted ? "Kanal bei YouTube abonniert." : "YouTube-Abo beendet."
        }
    }

    func save(to playlistID: String) {
        guard store.playlists.contains(where: { $0.id == playlistID }) else {
            message = "Bitte eine deiner aktuell geladenen Playlists wählen."; return
        }
        perform(write: true) { [self] revision in
            let inserted = try await store.api.saveToPlaylist(videoID: videoID, playlistID: playlistID, expected: revision)
            return inserted ? "In deiner YouTube-Playlist gespeichert." : "Das Video ist bereits in dieser Playlist."
        }
    }

    func post(text: String, parentID: String?) {
        guard let video else { return }
        do { _ = try YouTubeActionPolicy.comment(text) }
        catch { message = error.localizedDescription; return }
        if let parentID, !comments.contains(where: { $0.id == parentID }) {
            message = "Der ausgewählte Kommentar ist nicht mehr geöffnet."; return
        }
        perform(write: true) { [self] revision in
            let created = try await store.api.postComment(videoID: video.id, channelID: video.channelID, text: text, parentID: parentID, expected: revision)
            try store.checkSession(revision)
            if let parentID {
                replies[parentID] = unique((replies[parentID] ?? []) + [created])
                comments = comments.map { item in
                    guard item.id == parentID else { return item }
                    return YouTubeComment(id: item.id, author: item.author, text: item.text, likeCount: item.likeCount,
                                          replyCount: item.replyCount + 1, parentID: item.parentID)
                }
            } else { comments = unique([created] + comments) }
            postedSequence += 1
            return "Von YouTube angenommen. Die Veröffentlichung kann von der Kanalmoderation abhängen."
        }
    }

    func loadMoreComments() {
        guard let token = nextComments else { return }
        perform(write: false) { [self] revision in
            let page = try await store.api.comments(videoID: videoID, token: token, expected: revision)
            try store.checkSession(revision)
            comments = unique(comments + page.items)
            nextComments = page.nextPageToken; hasMoreComments = nextComments != nil
            return ""
        }
    }

    func loadReplies(parentID: String) {
        guard comments.contains(where: { $0.id == parentID }), !repliesLoaded.contains(parentID) || moreReplies.contains(parentID) else { return }
        let token = nextReplies[parentID]
        perform(write: false) { [self] revision in
            let page = try await store.api.replies(parentID: parentID, token: token, expected: revision)
            try store.checkSession(revision)
            replies[parentID] = unique((replies[parentID] ?? []) + page.items)
            repliesLoaded.insert(parentID)
            nextReplies[parentID] = page.nextPageToken
            if page.nextPageToken != nil { moreReplies.insert(parentID) } else { moreReplies.remove(parentID) }
            return ""
        }
    }

    private func perform(write: Bool, action: @escaping @MainActor (UInt64) async throws -> String) {
        guard !busy, let revision = loadedRevision, video != nil else { return }
        guard revision == store.sessionRevision else { message = AccountError.sessionChanged.localizedDescription; return }
        guard !write || store.hasInteractionPermission else { message = AccountError.consentRequired.localizedDescription; return }
        let identifier = requestID
        busy = true; message = nil
        work = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if requestID == identifier { busy = false; work = nil } }
            do {
                try ensure(identifier, revision)
                let result = try await action(revision)
                try ensure(identifier, revision)
                message = result.isEmpty ? nil : result
            } catch {
                guard requestID == identifier, revision == store.sessionRevision, !(error is CancellationError) else { return }
                if write && !(error is AccountError) {
                    message = "Keine sichere Bestätigung von YouTube erhalten. Prüfe den aktuellen Zustand vor einer erneuten Aktion. Es erfolgt keine automatische Wiederholung."
                } else { message = error.localizedDescription }
                store.handle(error, expected: revision)
            }
        }
    }

    private func ensure(_ identifier: UUID, _ revision: UInt64) throws {
        try Task.checkCancellation()
        guard requestID == identifier else { throw CancellationError() }
        try store.checkSession(revision)
    }

    private func unique(_ values: [YouTubeComment]) -> [YouTubeComment] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0.id).inserted }
    }

    func close() {
        requestID = UUID(); work?.cancel(); work = nil; busy = false; loadedRevision = nil
    }
}

@MainActor
struct VideoActionsSheet: View {
    @ObservedObject var store: AccountStore
    @StateObject private var model: VideoActionsModel
    @Environment(\.dismiss) private var dismiss
    @State private var commentText = ""
    @State private var replyParent: YouTubeComment?

    init(store: AccountStore, videoID: String, channelID: String? = nil) {
        self.store = store
        // Fetch the real channel from YouTube; a caller-supplied channel cannot authorize a write.
        _model = StateObject(wrappedValue: VideoActionsModel(store: store, videoID: videoID))
    }

    var body: some View {
        NavigationStack {
            Group {
                if !store.isSignedIn {
                    AccountConnectionPrompt(store: store)
                } else {
                    List {
                        if let video = model.video {
                            Section {
                                Text(video.title).font(.headline)
                                Text(video.channelTitle).font(.subheadline).foregroundStyle(.secondary)
                            }.listRowBackground(AccountPalette.card)
                        }

                        if !store.hasInteractionPermission {
                            Section {
                                Button("Interaktionen mit Google freigeben") { Task { await store.authorizeInteractions() } }
                                    .disabled(store.isAuthenticating || model.busy)
                                Text("Die Freigabe kann ein anderes Konto auswählen. Anschließend werden die Daten neu geladen. Wähle danach deine gewünschte Aktion erneut.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }.listRowBackground(AccountPalette.card)
                        }

                        Section("Bewertung und Kanal") {
                            HStack {
                                Button { model.setRating(model.rating == .like ? .none : .like) } label: {
                                    Label("Gefällt mir", systemImage: model.rating == .like ? "hand.thumbsup.fill" : "hand.thumbsup")
                                }.disabled(model.rating == nil || !store.hasInteractionPermission || model.busy)
                                Spacer()
                                Button { model.setRating(model.rating == .dislike ? .none : .dislike) } label: {
                                    Label("Gefällt nicht", systemImage: model.rating == .dislike ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                                }.disabled(model.rating == nil || !store.hasInteractionPermission || model.busy)
                            }.buttonStyle(.borderless)
                            Button { model.toggleSubscription() } label: {
                                Label(model.subscriptionID == nil ? "Kanal abonnieren" : "Abo beenden",
                                      systemImage: model.subscriptionID == nil ? "plus.circle" : "checkmark.circle.fill")
                            }.disabled(!model.subscriptionKnown || !store.hasInteractionPermission || model.busy)
                        }.listRowBackground(AccountPalette.card)

                        Section("In Playlist speichern") {
                            ForEach(store.playlists) { playlist in
                                Button { model.save(to: playlist.id) } label: { Label(playlist.title, systemImage: "text.badge.plus") }
                                    .disabled(model.video == nil || !store.hasInteractionPermission || model.busy)
                            }
                            if store.hasMorePlaylists {
                                Button("Weitere Playlists laden") { Task { await store.loadMorePlaylists() } }.disabled(store.playlistsLoading)
                            }
                            if store.playlists.isEmpty { Text("Keine eigenen Playlists geladen.").foregroundStyle(.secondary) }
                        }.listRowBackground(AccountPalette.card)

                        Section(replyParent == nil ? "Kommentar schreiben" : "Antwort an \(replyParent?.author ?? "")") {
                            TextEditor(text: $commentText).frame(minHeight: 86).accessibilityLabel("Kommentartext")
                                .disabled(!store.hasInteractionPermission || model.busy)
                            HStack {
                                Text("\(commentText.utf16.count) / 5.000").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("Senden") { model.post(text: commentText, parentID: replyParent?.id) }
                                    .disabled(!store.hasInteractionPermission || model.busy || model.video == nil || (try? YouTubeActionPolicy.comment(commentText)) == nil)
                            }
                            if replyParent != nil { Button("Antwortauswahl aufheben") { replyParent = nil } }
                        }.listRowBackground(AccountPalette.card)

                        Section("Kommentare") {
                            AccountErrorRow(message: model.commentsMessage)
                            ForEach(model.comments) { comment in
                                VStack(alignment: .leading, spacing: 8) {
                                    commentContent(comment)
                                    HStack {
                                        Button("Antworten") { replyParent = comment }
                                        if comment.replyCount > 0 || model.moreReplies.contains(comment.id) {
                                            Button(model.moreReplies.contains(comment.id) ? "Weitere Antworten" : "\(comment.replyCount) Antworten") {
                                                model.loadReplies(parentID: comment.id)
                                            }
                                        }
                                    }.font(.caption).buttonStyle(.borderless).disabled(model.busy || !store.hasInteractionPermission)
                                    ForEach(model.replies[comment.id] ?? []) { reply in
                                        commentContent(reply).padding(.leading, 20)
                                    }
                                }.padding(.vertical, 5)
                            }
                            if model.hasMoreComments {
                                Button("Weitere Kommentare laden") { model.loadMoreComments() }.disabled(model.busy)
                            }
                        }.listRowBackground(AccountPalette.card)

                        if model.busy || store.isAuthenticating { ProgressView("YouTube-Anfrage läuft …").listRowBackground(AccountPalette.card) }
                        AccountErrorRow(message: model.message).listRowBackground(AccountPalette.card)
                        AccountErrorRow(message: store.errorMessage).listRowBackground(AccountPalette.card)
                    }.scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(AccountPalette.background)
            .tint(AccountPalette.mint).navigationTitle("YouTube-Aktionen").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fertig") { model.close(); dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await model.load() } } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("YouTube-Aktionen aktualisieren").disabled(model.busy || !store.isSignedIn)
                }
            }
            .task(id: "\(store.sessionRevision)-\(store.isSignedIn)") {
                commentText = ""; replyParent = nil
                await store.loadIfNeeded()
                await model.load()
            }
            .onChange(of: model.postedSequence) { _, _ in commentText = ""; replyParent = nil }
            .onDisappear { model.close() }
        }
    }

    private func commentContent(_ comment: YouTubeComment) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(comment.author).font(.caption.weight(.semibold)).foregroundStyle(AccountPalette.mint)
            Text(comment.text).font(.subheadline).textSelection(.enabled)
            Label("\(comment.likeCount)", systemImage: "hand.thumbsup").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct HistoryCarousel:View {
    @ObservedObject var store:HistoryStore
    let onOpen:(URL)->Void
    let onShowAll:()->Void
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {Text("Verlauf").font(.headline);Spacer();Button("Alle anzeigen",action:onShowAll).font(.subheadline)}.padding(.horizontal,16)
            if store.recentEntries.isEmpty {
                Text(store.enabled ? "Deine angesehenen Videos erscheinen hier.":"Verlauf ist pausiert.").font(.footnote).foregroundStyle(.secondary).padding(.horizontal,16)
            } else {
                ScrollView(.horizontal,showsIndicators:false) {
                    HStack(spacing:12) {
                        ForEach(store.recentEntries) {entry in
                            Button {onOpen(entry.url)} label:{
                                VStack(alignment:.leading,spacing:6) {
                                    thumbnail(entry).frame(width:208,height:117).clipShape(RoundedRectangle(cornerRadius:12))
                                    Text(entry.title).font(.subheadline).foregroundStyle(.primary).lineLimit(2).frame(height:38,alignment:.top)
                                }.frame(width:208)
                            }.buttonStyle(.plain).accessibilityLabel("\(entry.title), fortsetzen bei \(entry.positionLabel)")
                        }
                    }.padding(.horizontal,16)
                }
            }
        }.padding(.vertical,12).background(Color.weiktubeBackground)
    }
    private func thumbnail(_ entry:HistoryEntry)->some View {
        ZStack(alignment:.bottomLeading) {
            AccountThumbnail(url:entry.thumbnailURL,symbol:"play.rectangle.fill",width:208,height:117)
            GeometryReader {geometry in Rectangle().fill(Color.weiktubeRed).frame(width:geometry.size.width*entry.progress,height:3).frame(maxHeight:.infinity,alignment:.bottom)}
        }
    }
}

struct HistoryScreen:View {
    @ObservedObject var store:HistoryStore
    var account:AccountStore?=nil
    let onOpen:(URL)->Void
    let onClear:()->Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear=false
    var body:some View {
        List {
            if let account {
                NavigationLink("Deine Playlists") {
                    PlaylistsScreen(store:account,onOpenVideo:{id in
                        guard YouTubeLinkRouter.validVideoID(id) else{return}
                        dismiss();onOpen(VideoLink(id:id).url)
                    })
                }
            }
            if let error=store.storageError {Text(error).foregroundStyle(.orange)}
            if store.entries.isEmpty {ContentUnavailableView("Noch kein Verlauf",systemImage:"clock",description:Text("Wiedergabe und Fortschritt werden lokal gespeichert, wenn der Verlauf aktiviert ist."))}
            ForEach(store.entries) {entry in
                Button {dismiss();onOpen(entry.url)} label:{
                    HStack(spacing:12) {
                        AccountThumbnail(url:entry.thumbnailURL,symbol:"play.rectangle.fill",width:112,height:63).clipShape(RoundedRectangle(cornerRadius:8))
                        VStack(alignment:.leading,spacing:5) {
                            Text(entry.title).font(.subheadline).foregroundStyle(.primary).lineLimit(2)
                            Text(entry.watchedAt,style:.date).font(.caption).foregroundStyle(.secondary)
                            if entry.position>0 {Text("Fortsetzen · \(entry.positionLabel)").font(.caption).foregroundStyle(Color.weiktubeAccent)}
                        }
                    }
                }.swipeActions {Button("Löschen",role:.destructive){store.remove(entry.id)}}
            }
        }.navigationTitle("Verlauf").toolbar {
            ToolbarItem(placement:.cancellationAction){Button("Fertig"){dismiss()}}
            ToolbarItem(placement:.primaryAction){Button("Leeren",role:.destructive){confirmClear=true}.disabled(store.entries.isEmpty)}
        }.confirmationDialog("Verlauf und gespeicherte Positionen löschen?",isPresented:$confirmClear,titleVisibility:.visible) {
            Button("Verlauf löschen",role:.destructive,action:onClear)
            Button("Abbrechen",role:.cancel){}
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

@MainActor
struct RootView:View {
    @ObservedObject var app:AppModel
    @ObservedObject private var player:PlayerCoordinator
    @ObservedObject private var settings:AppSettings
    @ObservedObject private var home:WebSession
    @AppStorage("weiktube.homeExplanationDismissed.v1") private var homeExplanationDismissed=false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var linkText=""
    @State private var searchText=""
    init(app:AppModel) { self.app=app;player=app.player;settings=app.settings;home=app.home }
    var body:some View {
        GeometryReader { geometry in
            let bottom:CGFloat=player.isFullscreen ? 0:60
            let expandedHeight=max(240,geometry.size.height-bottom)
            let miniWidth=min(196,geometry.size.width-24)
            let miniHeight=miniWidth / max(1,player.aspect)
            let fraction=player.isMini ? CGFloat(1):player.dragFraction
            let panelWidth=geometry.size.width+(miniWidth-geometry.size.width)*fraction
            let panelHeight=expandedHeight+(miniHeight-expandedHeight)*fraction
            let panelX=(geometry.size.width-miniWidth-12)*fraction
            let panelY=(geometry.size.height-bottom-miniHeight-12)*fraction
            ZStack(alignment:.topLeading) {
                VStack(spacing:0) {
                    header
                    tabContent.frame(maxWidth:.infinity,maxHeight:.infinity)
                    bottomBar.frame(height:60)
                }
                if player.hasPlayer {
                    PlayerPanel(player:player,sponsor:app.sponsor,dislikes:app.dislikes,
                                logicalSize:CGSize(width:geometry.size.width,height:max(1,expandedHeight-100)),
                                onActions:{player.pause();app.showActions=true;app.reconcilePlayback()})
                        .frame(width:panelWidth,height:panelHeight)
                        .offset(x:panelX,y:panelY)
                        .opacity(player.isPiP ? 0:1)
                        .allowsHitTesting(!player.isPiP)
                        .animation(reduceMotion ? nil:.easeInOut(duration:0.18),value:player.presentation.mode)
                }
            }
        }
        .background(Color.weiktubeBackground.ignoresSafeArea())
        .foregroundStyle(.primary).tint(.weiktubeAccent)
        .preferredColorScheme(app.colorScheme)
        .ignoresSafeArea(edges:player.isFullscreen ? .all:[])
        .statusBarHidden(player.isFullscreen)
        .task { await app.start() }
        .onOpenURL { app.open($0) }
        .onChange(of:scenePhase) { _,value in app.sceneChanged(value) }
        .onReceive(NotificationCenter.default.publisher(for:UIDevice.orientationDidChangeNotification)) { _ in player.orientationChanged(UIDevice.current.orientation) }
        .sheet(isPresented:$app.showSettings) { NavigationStack { SettingsScreen(app:app) } }
        .sheet(isPresented:$app.showHistory) { NavigationStack { HistoryScreen(store:app.history,account:app.account,onOpen:app.open,onClear:app.clearHistory) } }
        .sheet(isPresented:$app.showActions,onDismiss:{app.reconcilePlayback()}) {
            if let id=player.route?.videoID { VideoActionsSheet(store:app.account,videoID:id) }
        }
        .sheet(isPresented:$app.showLink) { linkSheet }
        .sheet(isPresented:$app.showSearch) { searchSheet }
        .alert("Weiktube",isPresented:Binding(get:{app.alertMessage != nil},set:{if !$0 {app.alertMessage=nil}})) {
            Button("OK",role:.cancel){app.alertMessage=nil}
        } message:{Text(app.alertMessage ?? "")}
    }
    private var header:some View {
        HStack(spacing:6) {
            if app.home.canGoBack && app.selectedTab == .home {
                IconButton(icon:"chevron.left",label:"Zurück") {app.back()}
            } else { WeiktubeLogo().frame(width:28,height:28) }
            Text("Weiktube").font(.title3.bold()).lineLimit(1)
            Spacer(minLength:0)
            IconButton(icon:"magnifyingglass",label:"YouTube durchsuchen") {app.showSearch=true}
            IconButton(icon:"person.crop.circle",label:"Konto") {app.select(.you)}
            Menu {
                Button("Video-Link öffnen",systemImage:"link") {app.showLink=true}
                Button("Verlauf",systemImage:"clock") {app.showHistory=true}
                Button("Einstellungen & Updates",systemImage:"gearshape") {app.showSettings=true}
                if app.selectedTab == .home || app.selectedTab == .shorts {
                    Button("Seite neu laden",systemImage:"arrow.clockwise") { app.selectedTab == .home ? app.home.reload():app.shorts.reload() }
                }
            } label:{Image(systemName:"ellipsis").frame(width:44,height:44)}.accessibilityLabel("Weitere Optionen")
        }.padding(.leading,12).padding(.trailing,4).frame(height:52).background(Color.weiktubeBackground)
    }
    @ViewBuilder private var tabContent:some View {
        switch app.selectedTab {
        case .home:
            VStack(spacing:0) {
                if !homeExplanationDismissed {
                    HStack(alignment:.top,spacing:12) {
                        Image(systemName:"globe").foregroundStyle(Color.weiktubeAccent)
                        VStack(alignment:.leading,spacing:4) {
                            Text("Originale YouTube-Startseite").font(.subheadline.weight(.semibold))
                            Text("Hier lädst du Inhalte von m.youtube.com. Deine Google-Freigabe unter „Du“ gilt für die nativen Kontoansichten und meldet diese Website nicht automatisch an.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Button {homeExplanationDismissed=true} label:{Image(systemName:"xmark").frame(width:32,height:32)}
                            .accessibilityLabel("Hinweis zur Startseite schließen")
                    }.padding(12).background(Color.weiktubeCard)
                }
                BrowserScreen(session:home)
            }
        case .shorts:ShortsScreen(session:app.shorts)
        case .adblock:NavigationStack {AdBlockScreen(service:app.adBlock,onReloadPages:app.reloadPages)}
        case .subscriptions:SubscriptionsScreen(store:app.account,onOpenVideo:app.openVideo)
        case .you:
            VStack(spacing:0) {
                HistoryCarousel(store:app.history,onOpen:app.open,onShowAll:{app.showHistory=true})
                AccountScreen(store:app.account,onOpenVideo:app.openVideo)
            }
        }
    }
    private var bottomBar:some View {
        HStack(spacing:0) {
            ForEach(MainTab.allCases) {tab in
                Button {app.select(tab)} label:{
                    VStack(spacing:4) {
                        Image(systemName:tab.symbol).font(.system(size:22,weight:app.selectedTab == tab ? .semibold:.regular))
                        Text(tab.title).font(.system(size:10,weight:app.selectedTab == tab ? .semibold:.regular)).lineLimit(1)
                    }.frame(maxWidth:.infinity,minHeight:56).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .foregroundStyle(app.selectedTab == tab ? Color.weiktubeAccent:Color.secondary)
                    .accessibilityLabel(tab.title).accessibilityAddTraits(app.selectedTab == tab ? .isSelected:[])
                    .accessibilityIdentifier("tab.\(tab.rawValue)")
            }
        }.background(Color.weiktubeBackground).overlay(alignment:.top){Divider().opacity(0.3)}
    }
    private var linkSheet:some View {
        NavigationStack {
            Form {
                Section("In Weiktube öffnen") {
                    TextField("YouTube- oder HTTPS-Video-Link",text:$linkText,axis:.vertical)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .accessibilityIdentifier("link.input")
                    Button("Link öffnen") { let value=linkText;linkText="";app.showLink=false;app.open(value) }
                        .disabled(linkText.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).accessibilityIdentifier("link.open")
                }
                Text("Videos, Shorts, Playlists, Kanäle und Zeitstempel werden erkannt. Geteilte Links kannst du auch über die Weiktube Share Extension sammeln.").font(.footnote).foregroundStyle(.secondary)
            }.navigationTitle("Video-Link").toolbar{ToolbarItem(placement:.cancellationAction){Button("Fertig"){app.showLink=false}}}
        }.presentationDetents([.medium,.large])
    }
    private var searchSheet:some View {
        NavigationStack {
            Form {
                TextField("YouTube durchsuchen",text:$searchText).submitLabel(.search).onSubmit(submitSearch)
                    .accessibilityIdentifier("search.input")
                Button("Suchen",action:submitSearch).disabled(searchText.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            }.navigationTitle("Suche").toolbar{ToolbarItem(placement:.cancellationAction){Button("Fertig"){app.showSearch=false}}}
        }.presentationDetents([.medium])
    }
    private func submitSearch(){let query=searchText;app.showSearch=false;app.search(query)}
}

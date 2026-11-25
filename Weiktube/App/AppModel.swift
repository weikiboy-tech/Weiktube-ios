// SPDX-License-Identifier: GPL-3.0-only
import AVFoundation
import Combine
import Foundation
import SwiftUI
import UIKit
import WebKit

enum MainTab: String, CaseIterable, Identifiable {
    case home, shorts, adblock, subscriptions, you
    var id: String { rawValue }
    var title: String { switch self { case .home: return "Startseite";case .shorts:return "Shorts";case .adblock:return "Adblock";case .subscriptions:return "Abos";case .you:return "Du" } }
    var symbol: String { switch self { case .home:return "house";case .shorts:return "play.rectangle.on.rectangle";case .adblock:return "shield";case .subscriptions:return "rectangle.stack";case .you:return "person.crop.circle" } }
}

@MainActor
final class AppModel: ObservableObject {
    let settings: AppSettings
    let history: HistoryStore
    let adBlock: AdBlockService
    let sponsor: SponsorBlockService
    let dislikes: ReturnDislikeService
    let account: AccountStore
    let player: PlayerCoordinator
    let home: WebSession
    let shorts: WebSession
    let network = NetworkMonitor()
    let ownership: PlaybackOwnership
    let releaseChecker=ReleaseChecker()
    @Published var selectedTab: MainTab = .home
    @Published var showSettings = false
    @Published var showHistory = false
    @Published var showLink = false
    @Published var showSearch = false
    @Published var showActions = false
    @Published var alertMessage: String?
    @Published private(set) var importing = false
    @Published private(set) var started = false
    private var scenePhase: ScenePhase = .active
    private var routeRevision = 0
    private var routeTask: Task<Bool,Never>?
    private var backgroundTask: Task<Void,Never>?
    private var audioReleaseTask: Task<Void,Never>?
    private var subscriptions = Set<AnyCancellable>()
    private var inbox: SharedLinkInbox?
    private let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")

    init() {
        let settings=AppSettings(),history=HistoryStore(enabled:settings.saveHistory)
        let adBlock=AdBlockService(),sponsor=SponsorBlockService(),dislikes=ReturnDislikeService()
        self.settings=settings;self.history=history;self.adBlock=adBlock;self.sponsor=sponsor;self.dislikes=dislikes
        account=AccountStore()
        home=WebSession(role:.home,adBlock:adBlock)
        shorts=WebSession(role:.shorts,adBlock:adBlock)
        player=PlayerCoordinator(adBlock:adBlock,sponsor:sponsor,dislikes:dislikes,history:history,settings:settings)
        ownership=PlaybackOwnership(home:home,shorts:shorts,player:player.web)
        ownership.pauseNative={ [weak player] in player?.native.pause() }
        player.onPresentationChanged={ [weak self] in self?.reconcilePlayback() }
        player.onPlaybackRequested={ [weak self] in
            guard let self else{return}
            if selectedTab == .shorts { selectedTab = .home }
            reconcilePlayback()
        }
        player.beforePlayback={ [weak self] in
            guard let self else { return false }
            reconcilePlayback()
            await ownership.waitForTransition()
            return scenePhase == .active && !showActions && selectedTab != .shorts && player.hasPlayer
        }
        let routeHandler: (URL)->Void = { [weak self] url in self?.open(url) }
        home.onRoute=routeHandler;shorts.onRoute=routeHandler;player.onRoute=routeHandler
        let externalHandler: (URL)->Void = { [weak self] url in self?.openExternal(url) }
        home.onExternalURL=externalHandler;shorts.onExternalURL=externalHandler;player.web.onExternalURL=externalHandler
        let accountHandler: ()->Void = { [weak self] in
            self?.select(.you)
            self?.alertMessage="Google unterstützt keine OAuth-Anmeldung in eingebetteten Webansichten. Verbinde dein Konto hier über die Systemanmeldung. Die native API-Anmeldung erzeugt keine angemeldete YouTube-Websitzung."
        }
        home.onAccountRequested=accountHandler;shorts.onAccountRequested=accountHandler;player.web.onAccountRequested=accountHandler
        settings.$saveHistory.dropFirst().sink { [weak self] enabled in
            self?.history.enabled=enabled
            if !enabled { self?.player.historyWasCleared() }
        }.store(in:&subscriptions)
        network.$useMobileQuality.combineLatest(settings.$wifiQuality,settings.$mobileQuality).sink { [weak self] mobilePolicy,wifi,mobile in
            self?.player.native.setQualityPreference(height:mobilePolicy ? mobile:wifi)
        }.store(in:&subscriptions)
        player.$snapshot.combineLatest(shorts.$snapshot).sink { [weak self] playerSample,shortsSample in
            self?.updateWakeLock(playerSample:playerSample,shortsSample:shortsSample)
        }.store(in:&subscriptions)
        inbox=try? SharedLinkInbox.configured()
        NotificationCenter.default.publisher(for:.weiktubeImportQueued).sink { [weak self] _ in
            Task { @MainActor [weak self] in await self?.importSharedLinks() }
        }.store(in:&subscriptions)
        // Configure movie audio without activating it during a paused cold restoration.
        try? AVAudioSession.sharedInstance().setCategory(.playback,mode:.moviePlayback)
    }
    func start() async {
        guard !started else{return};started=true
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        if !testing { home.load(URL(string:"https://m.youtube.com/")!) }
        // Home previews always stay silent: watch and Shorts are the only audible owners.
        await home.setSuspended(true)
        reconcilePlayback()
        await importSharedLinks()
        if !testing,routeRevision==0 {
            do {
                if let saved=try PlaybackRestorationStore().load(historyEnabled:settings.saveHistory) {
                    let historyRevision=history.revision
                    ownership.select(.none);await ownership.waitForTransition()
                    if routeRevision==0,settings.saveHistory,history.enabled,history.revision==historyRevision {
                        player.restoreSelection(saved);reconcilePlayback()
                    }
                }
            } catch {DiagnosticsStore.shared.record(.persistenceFailure)}
        }
        if !testing && settings.automaticFilterUpdateChecks {
            Task { [weak self] in await self?.adBlock.checkForUpdates(manual:false) }
        }
        if !testing && settings.automaticUpdateChecks {
            Task { [weak self] in await self?.releaseChecker.check(automatically:true) }
        }
    }
    func select(_ tab:MainTab) {
        cancelPendingRoute()
        if selectedTab == tab,tab == .home,!testing { home.load(URL(string:"https://m.youtube.com/")!) }
        selectedTab=tab
        if player.hasPlayer && !player.isMini && !player.isPiP { player.minimize() }
        if tab == .shorts {
            player.pause()
            if shorts.currentURL == nil && !testing { shorts.load(URL(string:"https://m.youtube.com/shorts")!) }
        }
        reconcilePlayback()
    }
    func open(_ url:URL) { open(url.absoluteString) }
    func open(_ raw:String) {
        guard let route=YouTubeLinkRouter.extractFirstRoute(from:raw) else {
            alertMessage="Kein unterstützter Link. Verwende einen YouTube-Link oder ein direktes öffentliches HTTPS-Video."
            DiagnosticsStore.shared.record(.importRejected);return
        }
        _ = schedule(route)
    }
    private func cancelPendingRoute() {
        routeRevision += 1
        routeTask?.cancel()
        routeTask = nil
    }
    private func schedule(_ route:MediaRoute) -> Task<Bool,Never> {
        routeRevision += 1
        let revision=routeRevision
        routeTask?.cancel()
        let task=Task { [weak self] in
            guard let self,!Task.isCancelled else{return false}
            switch route {
            case .video,.directMedia:
                ownership.select(.none)
                await ownership.waitForTransition()
                guard revision==routeRevision,!Task.isCancelled else{return false}
                player.open(route)
                if selectedTab == .shorts { selectedTab = .home }
                reconcilePlayback()
            case .shorts:
                if player.hasPlayer { player.minimize();player.pause() }
                selectedTab = .shorts
                if shorts.currentURL != route.url { shorts.load(route.url) }
                reconcilePlayback()
            case .home,.search,.channel,.playlist,.feed:
                selectedTab = .home
                if player.hasPlayer && !player.isMini { player.minimize() }
                home.load(route.url)
                reconcilePlayback()
            }
            return revision==routeRevision && !Task.isCancelled
        }
        routeTask=task
        return task
    }
    func openVideo(_ id:String) { if YouTubeLinkRouter.validVideoID(id) { open(VideoLink(id:id).url) } }
    func search(_ query:String) {
        let value=query.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !value.isEmpty else{return}
        open(MediaRoute.search(query:String(value.prefix(500))).url)
    }
    func back() {
        cancelPendingRoute()
        if player.isFullscreen { player.toggleFullscreen() }
        else if player.hasPlayer && !player.isMini && !player.isPiP { player.minimize() }
        else if selectedTab == .shorts { select(.home) }
        else if selectedTab == .home && home.canGoBack { home.back() }
        else if selectedTab != .home { select(.home) }
        else if player.isMini { player.close() }
    }
    func reconcilePlayback() {
        if scenePhase == .background {
            ownership.select(player.isPiP ? .pictureInPicture:.none,nativePlayer:player.isNative)
        } else if showActions {
            ownership.select(.none)
        } else if player.isPiP {
            ownership.select(.pictureInPicture,nativePlayer:player.isNative)
        } else if selectedTab == .shorts && (!player.hasPlayer || player.isMini) {
            ownership.select(.shorts)
        } else if player.hasPlayer && !player.restoredPaused {
            ownership.select(.player,nativePlayer:player.isNative)
        } else { ownership.select(.none) }
        updateWakeLock()
        releaseAudioIfUnowned()
    }
    private func releaseAudioIfUnowned() {
        audioReleaseTask?.cancel()
        let shouldRelease = (!player.hasPlayer && selectedTab != .shorts) || (scenePhase == .background && !player.isPiP)
        guard shouldRelease else{return}
        audioReleaseTask=Task { [weak self] in
            guard let self else{return}
            await ownership.waitForTransition()
            guard !Task.isCancelled,
                  (!player.hasPlayer && selectedTab != .shorts) || (scenePhase == .background && !player.isPiP) else{return}
            try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
        }
    }
    private func updateWakeLock(playerSample:MediaSnapshot?=nil,shortsSample:MediaSnapshot?=nil) {
        let inApp=scenePhase == .active && !showActions && !player.isPiP
        let shortsOwns=selectedTab == .shorts && (!player.hasPlayer || player.isMini)
        let playing=shortsOwns ? (shortsSample ?? shorts.snapshot).playing:
            (player.hasPlayer && !player.restoredPaused && (playerSample ?? player.snapshot).playing)
        UIApplication.shared.isIdleTimerDisabled=inApp && playing
    }
    func sceneChanged(_ phase:ScenePhase) {
        scenePhase=phase
        updateWakeLock()
        backgroundTask?.cancel()
        if phase != .active { player.saveRestoration(force:true);player.restoreBrightness();player.hold(false) }
        if phase == .background {
            backgroundTask=Task { [weak self] in
                try? await Task.sleep(for:.milliseconds(350))
                guard !Task.isCancelled,let self,scenePhase == .background else{return}
                if !player.isPiP { player.pause() }
                reconcilePlayback()
                await history.flush()
            }
        } else if phase == .active {
            reconcilePlayback()
            Task { await importSharedLinks() }
        }
    }
    func importSharedLinks() async {
        guard !importing,let inbox else{return};importing=true
        defer{importing=false}
        do {
            let items=try await inbox.pending()
            guard let latest=items.last,let route=YouTubeLinkRouter.route(latest.url) else{return}
            let task=schedule(route)
            guard await task.value,!Task.isCancelled else{return}
            try await inbox.acknowledge(Set(items.map(\.id)))
        } catch { alertMessage="Geteilte Links konnten nicht geladen werden. Prüfe die App-Group-Konfiguration." }
    }
    func clearHistory() { history.clear();player.historyWasCleared() }
    func clearWebsiteData() async {
        cancelPendingRoute()
        player.close();ownership.select(.none);await ownership.waitForTransition()
        await WKWebsiteDataStore.default().removeData(ofTypes:WKWebsiteDataStore.allWebsiteDataTypes(),modifiedSince:.distantPast)
        if !testing { home.reload();shorts.reload() }
        reconcilePlayback()
        alertMessage="Website-Daten wurden gelöscht. Verlauf und native Google-Anmeldung werden unabhängig davon verwaltet."
    }
    private func openExternal(_ url:URL) {
        guard WebSession.permitsExternalURL(url) else{return}
        UIApplication.shared.open(url,options:[:]) { [weak self] opened in
            guard !opened else{return}
            Task { @MainActor [weak self] in self?.alertMessage="Dieser Link konnte nicht im Browser geöffnet werden." }
        }
    }
    func reloadPages() { home.reload();shorts.reload();if player.hasPlayer{player.retry()} }
    var colorScheme:ColorScheme? { switch settings.appearance {case .system:return nil;case .dark:return .dark;case .light:return .light} }
}

// SPDX-License-Identifier: GPL-3.0-only
import AVFoundation
import Combine
import SwiftUI
import UIKit

@MainActor
final class PlayerCoordinator: ObservableObject {
    let web: WebSession
    let native: NativePlayback
    let sponsor: SponsorBlockService
    let dislikes: ReturnDislikeService
    let history: HistoryStore
    let settings: AppSettings
    private let adBlock: AdBlockService
    @Published private(set) var route: MediaRoute?
    @Published private(set) var snapshot = MediaSnapshot()
    @Published private(set) var presentation = PlayerPresentationState()
    @Published private(set) var feedback: String?
    @Published var showVolume = false
    @Published var originalControls = false
    @Published var dragFraction: CGFloat = 0
    @Published private(set) var resumedAt: Double = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var restoredPaused=false
    private let restoration=PlaybackRestorationStore()
    var onPresentationChanged: (() -> Void)?
    var onRoute: ((URL) -> Void)?
    var onPlaybackRequested: (() -> Void)?
    var beforePlayback: (() async -> Bool)?
    private var playRequest: Task<Void, Never>?
    private var playbackIntent = 0
    private(set) var generation = 0
    private var historyRevision: UInt64 = 0
    private var pendingResume: Double?
    private var resumeInFlight = false
    private var initialPlayPending = false
    private var sponsorRequest: Task<Void, Never>?
    private var dislikeRequest: Task<Void, Never>?
    private var documentTask: Task<Void, Never>?
    private var resumeTask: Task<Void, Never>?
    private var resumeTimeoutTask: Task<Void, Never>?
    private var sponsorSeekTask: Task<Void, Never>?
    private var sponsorTaskRevision = UUID()
    private var dislikeTaskRevision = UUID()
    private var feedbackTask: Task<Void, Never>?
    private var originalBrightness: CGFloat?
    private weak var brightnessScreen: UIScreen?
    private var lastSeekTime = Date.distantPast
    private var seekTotal = 0.0
    private var gestureSeekTarget: Double?
    private var activeSeekRequests = 0
    private var userSeekRevision = UUID()
    private var userSeekTask: Task<Void, Never>?
    private struct WebsiteUserSeek {
        let generation: Int
        let documentGeneration: Int
        let videoID: String
        let elementID: String
        let target: Double
        let startedAt: Date
    }
    private var websiteUserSeek: WebsiteUserSeek?
    private var zoom = 1.0
    var currentZoom: Double { zoom }
    private var heldGeneration: Int?
    private var holdToken: UUID?
    private var serviceObservations = Set<AnyCancellable>()
    private var deletedHistorySelection = false
    private var lastPiP = false
    private var pipOriginalControls: Bool?
    private var renderedDislikeKey = ""
    private var adRecoveryTask: Task<Void,Never>?
    private var adRecoveryAttempts=0
    private var lastContentPosition=0.0
    private var lastContentPlaying=false

    init(adBlock: AdBlockService, sponsor: SponsorBlockService, dislikes: ReturnDislikeService,
         history: HistoryStore, settings: AppSettings, nativePlayback: NativePlayback? = nil) {
        self.native = nativePlayback ?? NativePlayback()
        self.sponsor = sponsor; self.dislikes = dislikes; self.history = history; self.settings = settings
        self.adBlock=adBlock
        web = WebSession(role: .player, adBlock: adBlock)
        web.onMedia = { [weak self] value in
            guard let self, !isNative else { return }
            receive(value)
        }
        web.onRoute = { [weak self] in self?.onRoute?($0) }
        web.onFullscreenRequested = { [weak self] in self?.toggleFullscreen() }
        web.onProcessTerminated = { [weak self] in
            guard let self,hasPlayer,!isNative else { return }
            cancelUserSeekAccounting()
            resumeTask?.cancel(); resumeTimeoutTask?.cancel(); resumeInFlight = false
            pendingResume = pendingResume ?? (snapshot.advertisement ? lastContentPosition:snapshot.position)
            initialPlayPending = !restoredPaused && (initialPlayPending || snapshot.playing)
        }
        native.onSample = { [weak self] value in
            guard let self, isNative, value.elementID == "native-\(generation)" else { return }
            receive(value)
        }
        native.onPiP = { [weak self] active in
            guard let self, isNative, native.pipController?.isPictureInPictureActive == active else { return }
            confirmedPiP(active)
        }
        sponsor.$settings.removeDuplicates().dropFirst().sink { [weak self] preferences in
            Task { @MainActor [weak self] in
                guard let self, self.sponsor.settings == preferences else { return }
                refreshSponsor()
                receive(snapshot)
            }
        }.store(in: &serviceObservations)
        dislikes.$enabled.removeDuplicates().dropFirst().sink { [weak self] enabled in
            Task { @MainActor [weak self] in
                guard let self, self.dislikes.enabled == enabled else { return }
                refreshDislikes()
                applyDislikeEstimate()
            }
        }.store(in: &serviceObservations)
        dislikes.$count.dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.applyDislikeEstimate() }
        }.store(in:&serviceObservations)
        native.$errorMessage.sink { [weak self] message in
            guard let self, isNative else { return }; errorMessage=message
        }.store(in:&serviceObservations)
        web.$errorMessage.sink { [weak self] message in
            guard let self, !isNative else { return }; errorMessage=message
        }.store(in:&serviceObservations)
    }
    var isNative: Bool { if case .directMedia = route { return true }; return false }
    var hasPlayer: Bool { route != nil }
    var isMini: Bool { presentation.mode == .mini }
    var isFullscreen: Bool { presentation.isFullscreen }
    var isPiP: Bool { presentation.mode == .pictureInPicture }
    var aspect: CGFloat {
        guard snapshot.width > 0, snapshot.height > 0 else { return 16 / 9 }
        return CGFloat(min(3, max(0.4, snapshot.width / snapshot.height)))
    }

    func open(_ newRoute: MediaRoute, restoringPosition:Double?=nil, restored:Bool=false) {
        guard newRoute.videoID != nil || { if case .directMedia = newRoute { return true }; return false }() else { return }
        if route?.videoID == newRoute.videoID, newRoute.videoID != nil, hasPlayer {
            expand()
            if let seconds = newRoute.startSeconds { seek(seconds) }
            if restoredPaused && !restored {play()}
            return
        }
        close(save: true)
        generation += 1
        route = newRoute
        presentation.reduce(.open(sourceID: newRoute.videoID ?? newRoute.url.absoluteString))
        historyRevision = history.revision
        deletedHistorySelection = false
        restoredPaused=restored
        pendingResume = restoringPosition ?? newRoute.startSeconds ?? newRoute.videoID.flatMap { history.resumePosition(for: $0) }
        resumedAt = (newRoute.startSeconds == nil ? pendingResume : nil) ?? 0
        initialPlayPending = !restored
        originalControls = true
        errorMessage = nil
        if !restored {history.record(route: newRoute, title: "", position: pendingResume ?? 0, duration: 0)}
        historyRevision = history.revision
        if let id = newRoute.videoID {
            let captured = generation
            documentTask = Task { [weak self] in
                guard let self, generation == captured, route?.videoID == id, !Task.isCancelled else { return }
                await web.showOriginalControls(effectiveOriginalControls)
                guard generation == captured, !Task.isCancelled else { return }
                web.load(newRoute.url, expectedVideoID: id)
            }
            refreshSponsor(); refreshDislikes()
        } else if case let .directMedia(url) = newRoute {
            native.open(url, generation: generation)
        }
        DiagnosticsStore.shared.record(.playerSelected)
        saveRestoration(force:true)
        if restored {presentation.reduce(.minimize)}
        onPresentationChanged?()
    }

    private func receive(_ value: MediaSnapshot) {
        guard let route else { return }
        if !isNative && value.videoID != route.videoID { return }
        if !snapshot.elementID.isEmpty, snapshot.elementID != value.elementID {
            cancelUserSeekAccounting()
        }
        if let pending = websiteUserSeek {
            let sameSource = pending.generation == generation && pending.documentGeneration == web.generation &&
                pending.videoID == value.videoID && pending.elementID == value.elementID
            if !sameSource || Date().timeIntervalSince(pending.startedAt) > 2 || value.live || value.advertisement || value.mediaErrorCode != 0 {
                websiteUserSeek = nil
            } else if !value.seeking {
                websiteUserSeek = nil
                if value.mediaEvent == "seeked", value.ready, value.seekable,
                   abs(value.position - pending.target) <= 0.35 {
                    sponsor.userSeek(to: value.position)
                }
            }
        }
        if !isNative, value.seeking, !snapshot.seeking, activeSeekRequests == 0,
           !resumeInFlight, pendingResume == nil, !value.live, !value.advertisement,
           !value.elementID.isEmpty, let id = route.videoID {
            cancelUserSeekAccounting()
            sponsor.cancelPendingForUserSeek()
            websiteUserSeek = WebsiteUserSeek(generation: generation, documentGeneration: web.generation,
                                              videoID: id, elementID: value.elementID, target: value.position, startedAt: Date())
        }
        snapshot = value
        DiagnosticsStore.shared.recordMedia(value)
        observeAdvertisement(value)
        if value.ready { applyDislikeEstimate() }
        if value.inPictureInPicture != lastPiP { confirmedPiP(value.inPictureInPicture) }
        guard !restoredPaused else{return}
        // Run the state machine for paused/blocked samples too, to retire stale prompts.
        if let id = route.videoID,
           let request = sponsor.update(position: value.position, duration: value.duration, videoID: id, generation: generation,
                                        isPlaying: value.playing, isSeeking: value.seeking || resumeInFlight || pendingResume != nil || !value.ready || !value.seekable,
                                        isLive: value.live, isAdvertisement: value.advertisement) {
            executeSponsorSeek(request)
        }
        guard !value.advertisement else { return }
        if !value.ready {
            // iPhone WebKit may preload only metadata until the first play request.
            if canRequestPlayback, pendingResume == nil || pendingResume == 0 {
                pendingResume = nil
                startOnceIfRequested()
            }
            return
        }
        if let seconds = pendingResume {
            // An explicit zero at the beginning needs no seek. Live media cannot promise stored resume.
            if value.live || (seconds == 0 && (!value.seekable || value.position <= 0.35)) {
                pendingResume = nil; resumeTimeoutTask?.cancel(); resumeTimeoutTask = nil
                if value.live && seconds > 0 { showFeedback("Livevideo: gespeicherte Position kann nicht übernommen werden.") }
            } else if value.seekable && !resumeInFlight {
                resumeInFlight = true
                resumeTimeoutTask?.cancel(); resumeTimeoutTask = nil
                let captured = generation
                resumeTask = Task { [weak self] in
                    guard let self, generation == captured, !Task.isCancelled else { return }
                    let result = await performSeek(seconds)
                    guard captured == generation, !Task.isCancelled else { return }
                    resumeInFlight = false; pendingResume = nil; resumeTask = nil
                    if result == nil { showFeedback("Wiedergabeposition konnte noch nicht übernommen werden.") }
                    startOnceIfRequested()
                }
                return
            } else if !resumeInFlight && resumeTimeoutTask == nil {
                let captured = generation
                resumeTimeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(8))
                    guard let self, !Task.isCancelled, generation == captured, pendingResume != nil, !resumeInFlight else { return }
                    pendingResume = nil; resumeTimeoutTask = nil
                    showFeedback("Das Video ist noch nicht spulbar. Wiedergabe startet ohne gespeicherte Position.")
                    startOnceIfRequested()
                }
            }
        }
        startOnceIfRequested()
        if let id = route.videoID, value.duration > 0, pendingResume == nil, !deletedHistorySelection, !value.live {
            history.updateProgress(videoID: id, title: value.title, position: value.position,
                                   duration: value.duration, ended: value.ended, expectedRevision: historyRevision)
        }
        if value.ready && !value.advertisement && !value.seeking {saveRestoration()}
    }
    private func refreshSponsor() {
        guard sponsor.enabled, let id = route?.videoID else {
            sponsorTaskRevision = UUID(); sponsorRequest?.cancel(); sponsorRequest = nil; return
        }
        guard sponsorRequest == nil else { return }
        let captured = generation
        let revision = UUID(); sponsorTaskRevision = revision
        sponsorRequest = Task { [weak self] in
            guard let self, captured == generation, route?.videoID == id, !Task.isCancelled else { return }
            defer { if sponsorTaskRevision == revision { sponsorRequest = nil } }
            await sponsor.load(videoID: id, generation: captured)
        }
    }
    private func observeAdvertisement(_ value:MediaSnapshot) {
        guard !isNative else{return}
        if !value.advertisement {
            adRecoveryTask?.cancel();adRecoveryTask=nil
            if value.ready && !value.seeking {lastContentPosition=value.position;lastContentPlaying=value.playing}
            return
        }
        guard adBlock.enabled,adBlock.preferences.ads,adRecoveryTask==nil,
              initialPlayPending || lastContentPlaying else{return}
        let captured=generation
        adRecoveryTask=Task { [weak self] in
            try? await Task.sleep(for:.seconds(1))
            guard let self,!Task.isCancelled,generation==captured,snapshot.advertisement,
                  adBlock.enabled,adBlock.preferences.ads,initialPlayPending || lastContentPlaying else{return}
            if adRecoveryAttempts==0 {
                adRecoveryAttempts=1
                pendingResume=pendingResume ?? (lastContentPosition>0 ? lastContentPosition:nil)
                initialPlayPending=true
                DiagnosticsStore.shared.record(.adRecoveryAttempt)
                adRecoveryTask=nil
                web.reload()
            } else {
                pause(reason: .adRecovery)
                errorMessage="Werbung wird weiterhin erkannt. Der Player bleibt angehalten. Prüfe die Filter oder öffne die originale Steuerung; ein weiterer automatischer Reload erfolgt nicht."
            }
        }
    }
    private func refreshDislikes() {
        guard dislikes.enabled, let id = route?.videoID else {
            dislikeTaskRevision = UUID(); dislikeRequest?.cancel(); dislikeRequest = nil; return
        }
        guard dislikeRequest == nil else { return }
        let captured = generation
        let revision = UUID(); dislikeTaskRevision = revision
        dislikeRequest = Task { [weak self] in
            guard let self, captured == generation, route?.videoID == id, !Task.isCancelled else { return }
            defer { if dislikeTaskRevision == revision { dislikeRequest = nil } }
            await dislikes.load(videoID: id, generation: captured)
        }
    }
    private func applyDislikeEstimate() {
        guard !isNative, let id=route?.videoID, web.snapshot.ready else {return}
        let label=dislikes.enabled ? dislikes.count.map{$0.formatted(.number.locale(Locale(identifier:"de_DE")))}:nil
        let key="\(generation)|\(web.generation)|\(label ?? "off")"
        guard key != renderedDislikeKey else{return}
        renderedDislikeKey=key
        let captured=generation
        Task { [weak self] in
            guard let self,captured==generation else{return}
            let result=await web.command("dislike",values:["videoID":id,"label":label as Any? ?? NSNull()])
            if captured==generation,result?["ok"] as? Bool != true {renderedDislikeKey=""}
        }
    }
    private var canRequestPlayback: Bool {
        if isNative { return snapshot.ready }
        return !snapshot.elementID.isEmpty && snapshot.videoID == route?.videoID && !snapshot.advertisement
    }
    private func startOnceIfRequested() {
        guard initialPlayPending, pendingResume == nil, canRequestPlayback else { return }
        initialPlayPending = false
        play()
    }
    func play() {
        guard hasPlayer else { return }
        restoredPaused=false
        playbackIntent += 1
        let intent = playbackIntent
        playRequest?.cancel()
        onPlaybackRequested?()
        let captured = generation
        playRequest = Task { [weak self] in
            guard let self else { return }
            let allowed = await beforePlayback?() ?? true
            guard allowed, captured == generation, hasPlayer, intent == playbackIntent, !Task.isCancelled else { return }
            guard canRequestPlayback else { initialPlayPending = true; return }
            if pendingResume != nil {initialPlayPending=true;receive(snapshot);return}
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
            if isNative { native.play() }
            else { _ = await web.command("play", elementID: snapshot.elementID) }
        }
    }
    func pause(reason: DiagnosticsStore.PauseReason = .control) {
        if hasPlayer { DiagnosticsStore.shared.recordPause(reason) }
        playbackIntent += 1
        playRequest?.cancel()
        adRecoveryTask?.cancel();adRecoveryTask=nil;lastContentPlaying=false
        initialPlayPending = false
        saveRestoration(force:true)
        if isNative { native.pause() }
        else {
            let captured = generation, elementID = snapshot.elementID
            Task { [weak self] in
                guard let self, captured == generation, hasPlayer else { return }
                _ = await web.command("pause", elementID: elementID)
            }
        }
    }
    func togglePlayback() { snapshot.playing ? pause() : play() }
    private func cancelUserSeekAccounting() {
        userSeekRevision = UUID()
        userSeekTask?.cancel(); userSeekTask = nil
        websiteUserSeek = nil
    }
    func seek(_ seconds: Double) {
        guard hasPlayer, seconds.isFinite else { return }
        let target = min(max(0, seconds), max(0, snapshot.duration))
        sponsorSeekTask?.cancel(); sponsorSeekTask = nil
        cancelUserSeekAccounting()
        sponsor.cancelPendingForUserSeek()
        resumeTask?.cancel(); resumeTimeoutTask?.cancel(); resumeInFlight = false; pendingResume = nil
        let captured = generation, revision = userSeekRevision, elementID = snapshot.elementID
        let documentGeneration = web.generation, nativeSource = isNative
        userSeekTask = Task { [weak self] in
            guard let self, captured == generation, revision == userSeekRevision, !Task.isCancelled,
                  snapshot.elementID == elementID, nativeSource || documentGeneration == web.generation else { return }
            defer { if revision == userSeekRevision { userSeekTask = nil } }
            let result = await performSeek(target)
            guard captured == generation, revision == userSeekRevision, !Task.isCancelled,
                  snapshot.elementID == elementID, nativeSource || documentGeneration == web.generation else { return }
            if let actual = result { sponsor.userSeek(to: actual) }
            else { DiagnosticsStore.shared.record(.seekRejected) }
        }
    }
    private func performSeek(_ seconds: Double) async -> Double? {
        guard hasPlayer, seconds.isFinite, !Task.isCancelled else { return nil }
        websiteUserSeek = nil
        let captured = generation
        activeSeekRequests += 1
        defer { if captured == generation { activeSeekRequests = max(0, activeSeekRequests - 1) } }
        if isNative {
            let actual = await native.seek(to: seconds)
            return captured == generation && !Task.isCancelled ? actual : nil
        }
        let result = await web.command("seek", values: ["seconds": seconds], elementID: snapshot.elementID)
        guard captured == generation, !Task.isCancelled, result?["ok"] as? Bool == true,
              let actual = result?["position"] as? Double, actual.isFinite else { return nil }
        return actual
    }
    func skipGesture(direction: Double) {
        guard settings.doubleTapSeek, snapshot.seekable else { return }
        let delta = Double(settings.seekSeconds) * direction
        let now = Date()
        if now.timeIntervalSince(lastSeekTime) > 0.7 || delta * seekTotal < 0 {
            seekTotal = 0; gestureSeekTarget = snapshot.position
        }
        seekTotal += delta; lastSeekTime = now
        let target = min(snapshot.duration, max(0, (gestureSeekTarget ?? snapshot.position) + delta))
        gestureSeekTarget = target
        seek(target)
        showFeedback("\(seekTotal < 0 ? "−" : "+")\(Int(abs(seekTotal))) s")
    }
    func setRate(_ rate: Double) {
        guard rate.isFinite else { return }
        if isNative {
            if !native.setRate(rate) { showFeedback("Diese Geschwindigkeit wird nicht unterstützt.") }
        } else {
            let captured = generation, elementID = snapshot.elementID
            Task { [weak self] in
                guard let self, captured == generation, hasPlayer else { return }
                let result = await web.command("rate", values: ["rate": rate], elementID: elementID)
                guard captured == generation else { return }
                if result?["ok"] as? Bool != true { showFeedback("Diese Geschwindigkeit wurde vom Player nicht bestätigt.") }
            }
        }
    }
    func supportedHoldRates() async -> [Double] {
        if isNative { return native.supportedHoldRates }
        return await web.reportedHoldRates()
    }

    func hold(_ active: Bool) {
        if !active {
            let held = heldGeneration; heldGeneration = nil; holdToken = nil
            guard held == generation else { return }
            if isNative { native.release() } else {
                Task { [weak self] in
                    guard let self, generation == held, heldGeneration == nil else { return }
                    _ = await web.command("release")
                }
            }
            feedback = nil
            return
        }
        guard settings.holdToSpeed, snapshot.ready, snapshot.playing, !snapshot.ended else { return }
        heldGeneration = generation
        let token = UUID(); holdToken = token
        let rate = settings.holdSpeed
        if isNative {
            if native.hold(rate: rate) { showFeedback("\(rate.formatted())×", persistent: true) }
        }
        else {
            let captured = generation
            Task { [weak self] in
                guard let self, captured == generation, holdToken == token else { return }
                let element = snapshot.elementID
                let rates = await web.reportedHoldRates()
                guard captured == generation, holdToken == token, element == snapshot.elementID, rates.contains(rate) else { return }
                let result = await web.command("hold", values: ["rate": rate], elementID: element)
                guard captured == generation else { return }
                guard holdToken == token else {
                    if holdToken == nil { _ = await web.command("release") }
                    return
                }
                if result?["ok"] as? Bool == true { showFeedback("\(rate.formatted())×", persistent: true) }
            }
        }
    }
    func setZoom(_ value: Double, anchorX: Double = 0.5, anchorY: Double = 0.5) {
        zoom = min(8, max(1, value))
        if isNative { native.setZoom(zoom,anchorX:anchorX,anchorY:anchorY) }
        else {
            let captured = generation, scale = zoom, elementID = snapshot.elementID
            Task { [weak self] in
                guard let self, captured == generation, hasPlayer else { return }
                _ = await web.command("zoom", values: ["scale": scale, "x":anchorX, "y":anchorY], elementID: elementID)
            }
        }
    }
    func beginBrightness() {
        guard originalBrightness == nil, let screen = activeScene?.screen else { return }
        brightnessScreen = screen; originalBrightness = screen.brightness
    }
    func changeBrightness(delta: Double) {
        guard settings.brightnessGesture else { return }
        beginBrightness()
        guard let screen = brightnessScreen else { return }
        screen.brightness = min(1, max(CGFloat(PlayerGestureLimits.minimumBrightness), screen.brightness + delta))
        showFeedback("Helligkeit \(Int(screen.brightness * 100)) %", persistent: true)
    }
    func endGesture() { hold(false); if feedback != nil { showFeedback(feedback ?? "") } }
    func restoreBrightness() {
        if let originalBrightness { brightnessScreen?.brightness = originalBrightness }
        originalBrightness = nil; brightnessScreen = nil
    }
    func expand() { presentation.reduce(.expand); dragFraction = 0; syncOriginalControls(); onPresentationChanged?() }
    func minimize() {
        hold(false); restoreBrightness(); setZoom(1)
        presentation.reduce(.minimize); dragFraction = 0; syncOriginalControls()
        if let scene = activeScene, scene.interfaceOrientation.isLandscape { requestOrientation(.portrait) }
        onPresentationChanged?()
    }
    func toggleFullscreen() {
        let wasFullscreen = isFullscreen
        presentation.reduce(.toggleFullscreen)
        syncOriginalControls()
        setZoom(1)
        requestOrientation(wasFullscreen ? .portrait : .landscapeRight)
        DiagnosticsStore.shared.record(wasFullscreen ? .fullscreenExited : .fullscreenEntered)
        onPresentationChanged?()
    }
    func orientationChanged(_ value: UIDeviceOrientation) {
        let orientation: PlayerOrientation
        switch value {
        case .portrait: orientation = .portrait
        case .landscapeLeft: orientation = .landscapeLeft
        case .landscapeRight: orientation = .landscapeRight
        case .portraitUpsideDown: orientation = .inverted
        default: return
        }
        let previous = presentation.mode
        presentation.reduce(.orientationChanged(orientation))
        if previous != presentation.mode { setZoom(1); syncOriginalControls(); onPresentationChanged?() }
    }
    private func requestOrientation(_ mask: UIInterfaceOrientationMask) {
        guard let scene = activeScene else { return }
        scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { [weak self] _ in
            Task { @MainActor in self?.showFeedback("Die aktuelle Fensterkonfiguration erlaubt diese Drehung nicht.") }
        }
    }
    private var activeScene: UIWindowScene? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
    }
    func togglePiP() {
        guard snapshot.pictureInPictureAvailable || isPiP else { showFeedback("Picture-in-Picture wird für dieses Video derzeit nicht angeboten."); return }
        setZoom(1)
        if isNative { native.togglePiP() }
        else {
            let captured = generation
            Task { [weak self] in
            guard let self, captured == generation, hasPlayer else { return }
            let result = await web.command("pip", elementID: snapshot.elementID)
            guard captured == generation else { return }
            if result?["ok"] as? Bool != true { showFeedback("Starte Picture-in-Picture über die originale Videosteuerung, falls verfügbar.") }
        } }
    }
    private func confirmedPiP(_ active: Bool) {
        guard hasPlayer, active != lastPiP else { return }
        if active { pipOriginalControls = effectiveOriginalControls }
        lastPiP = active
        presentation.reduce(active ? .didEnterPictureInPicture : .didExitPictureInPicture(restoreInterface: true))
        if !active { pipOriginalControls = nil }
        syncOriginalControls()
        DiagnosticsStore.shared.record(active ? .pipEntered : .pipExited)
        onPresentationChanged?()
    }
    // The miniplayer crops the retained viewport natively, without changing the document layout.
    private var effectiveOriginalControls: Bool {
        if presentation.mode == .pictureInPicture { return pipOriginalControls ?? originalControls }
        return originalControls && presentation.mode != .fullscreen
    }
    var showingOriginalControls: Bool { effectiveOriginalControls }
    private func syncOriginalControls() {
        guard hasPlayer, !isNative else { return }
        let captured = generation
        Task { [weak self] in
            guard let self, generation == captured, !Task.isCancelled else { return }
            await web.showOriginalControls(effectiveOriginalControls)
        }
    }
    func showOriginalPlayerControls() {
        if presentation.mode == .fullscreen {
            originalControls = true
            presentation.reduce(.exitFullscreen); requestOrientation(.portrait)
            syncOriginalControls(); onPresentationChanged?()
        } else {
            originalControls.toggle(); syncOriginalControls()
        }
    }
    func skipSponsorManually() { if let request = sponsor.skipManual() { executeSponsorSeek(request) } }
    func undoSponsorSkip() { if let request = sponsor.undo() { executeSponsorSeek(request) } }
    private func executeSponsorSeek(_ request: SponsorSeekRequest) {
        guard request.videoID == route?.videoID, request.generation == generation else { return }
        let captured = generation
        sponsorSeekTask?.cancel()
        sponsorSeekTask = Task { [weak self] in
            guard let self, captured == generation, request.videoID == route?.videoID, !Task.isCancelled else { return }
            let actual = await performSeek(request.target)
            guard captured == generation, !Task.isCancelled, let actual else { return }
            sponsor.completeSeek(request: request, actualPosition: actual)
            sponsorSeekTask = nil
        }
    }
    func restart() { pendingResume = nil; resumedAt = 0; seek(0); play() }
    func retry() {
        cancelUserSeekAccounting()
        guard hasPlayer else { return }
        resumeTask?.cancel(); resumeTimeoutTask?.cancel(); resumeInFlight = false
        pendingResume = pendingResume ?? (snapshot.advertisement ? lastContentPosition:snapshot.position)
        initialPlayPending = !restoredPaused && (initialPlayPending || snapshot.playing)
        if isNative, case let .directMedia(url) = route { native.open(url, generation: generation) }
        else { web.reload() }
    }
    func historyWasCleared() { deletedHistorySelection = true;try? restoration.clear() }
    func restoreSelection(_ saved:PlaybackRestorationSnapshot) {
        open(saved.route,restoringPosition:saved.position,restored:true)
    }
    func saveRestoration(force:Bool=false) {
        guard let route,settings.saveHistory,!deletedHistorySelection else{return}
        // Loading/ad samples must never overwrite an explicit timestamp or saved resume.
        let position=pendingResume ?? (snapshot.live || snapshot.ended ? 0:(snapshot.advertisement ? lastContentPosition:snapshot.position))
        do {try restoration.store(route:route,position:min(86400,max(0,position)),historyEnabled:true,force:force)}
        catch {DiagnosticsStore.shared.record(.persistenceFailure)}
    }
    func close(save: Bool = true) {
        cancelUserSeekAccounting()
        playbackIntent += 1
        playRequest?.cancel()
        adRecoveryTask?.cancel();adRecoveryTask=nil
        adRecoveryAttempts=0;lastContentPosition=0;lastContentPlaying=false
        try? restoration.clear();restoredPaused=false
        if save, let id = route?.videoID, snapshot.ready, !snapshot.advertisement, !snapshot.live,
           pendingResume == nil,!resumeInFlight,!deletedHistorySelection {
            history.updateProgress(videoID: id, title: snapshot.title, position: snapshot.position, duration: snapshot.duration, ended: snapshot.ended, expectedRevision: historyRevision, force: true)
        }
        sponsorTaskRevision = UUID(); sponsorRequest?.cancel(); sponsorRequest = nil
        dislikeTaskRevision = UUID(); dislikeRequest?.cancel(); dislikeRequest = nil
        documentTask?.cancel(); documentTask = nil
        resumeTask?.cancel(); resumeTask = nil
        resumeTimeoutTask?.cancel(); resumeTimeoutTask = nil
        sponsorSeekTask?.cancel(); sponsorSeekTask = nil
        feedbackTask?.cancel()
        hold(false); restoreBrightness()
        native.close()
        route = nil; snapshot = MediaSnapshot(); presentation.reduce(.close)
        generation += 1; pendingResume = nil; resumeInFlight = false; initialPlayPending = false; lastPiP = false
        activeSeekRequests = 0; gestureSeekTarget = nil; seekTotal = 0; lastSeekTime = .distantPast; pipOriginalControls = nil
        let closedGeneration = generation
        Task { [weak self] in
            guard let self, route == nil, generation == closedGeneration else { return }
            await web.setSuspended(true)
        }
        sponsor.reset(); dislikes.reset(); dragFraction = 0; feedback = nil; showVolume = false
        DiagnosticsStore.shared.record(.playerClosed)
        onPresentationChanged?()
    }
    func showFeedback(_ message: String, persistent: Bool = false) {
        feedbackTask?.cancel(); feedback = message
        guard !persistent else { return }
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }; self?.feedback = nil
        }
    }
}

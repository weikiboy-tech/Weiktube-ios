// SPDX-License-Identifier: GPL-3.0-only
import AVFoundation
import AVKit
import Combine
import SwiftUI

/// AVPlayer is used only for explicitly supplied public HTTPS media, never extracted YouTube streams.
@MainActor
final class NativePlayback: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    let player: AVPlayer
    let layer: AVPlayerLayer
    private(set) var pipController: AVPictureInPictureController?
    var onSample: ((MediaSnapshot) -> Void)?
    var onPiP: ((Bool) -> Void)?
    private var timeObserver: Any?
    private var itemObservation: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?
    private var endedObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var generation = 0
    private var seekRevision = 0
    private var playbackRevision = 0
    private var replayTask: Task<Void,Never>?
    private var ended = false
    private var seeking = false
    @Published private(set) var errorMessage: String?
    private var title = "Direktes Video"
    private var zoom: CGFloat = 1
    private var baseRate: Float = 1
    private var heldRate: Float?
    private var maximumHeight = 0

    override init() {
        let nativePlayer = AVPlayer()
        player = nativePlayer
        layer = AVPlayerLayer(player: nativePlayer)
        super.init()
        layer.videoGravity = .resizeAspect
        player.automaticallyWaitsToMinimizeStalling = true
        player.preventsDisplaySleepDuringVideoPlayback = true
        if AVPictureInPictureController.isPictureInPictureSupported() {
            pipController = AVPictureInPictureController(playerLayer: layer)
            pipController?.delegate = self
            pipController?.canStartPictureInPictureAutomaticallyFromInline = true
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.sample() }
        }
        statusObservation = player.observe(\.timeControlStatus) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.sample() }
        }
    }

    func open(_ url: URL, generation: Int) {
        close()
        guard YouTubeLinkRouter.directMediaAllowed(url) else {
            errorMessage = "Dieser Direktlink wird nicht unterstützt. Erforderlich ist ein öffentlicher HTTPS-Medienlink ohne YouTube-Stream-Extraktion."
            return
        }
        self.generation = generation
        title = String(url.deletingPathExtension().lastPathComponent.prefix(200))
        let item = AVPlayerItem(url: url)
        item.preferredMaximumResolution = preferredResolution
        itemObservation = item.observe(\.status, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.sample() }
        }
        endedObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self, weak item] _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.player.currentItem === item else { return }
                self.ended = true
                self.sample()
            }
        }
        failureObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { [weak self, weak item] _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.player.currentItem === item else { return }
                self.errorMessage = "Das direkte Video konnte nicht weiter abgespielt werden. Prüfe den Link und die Verbindung."
                self.sample()
            }
        }
        player.replaceCurrentItem(with: item)
        // The coordinator starts playback only after competing audio owners are revoked.
        player.pause()
        sample()
    }
    func play() {
        guard player.currentItem != nil else { return }
        playbackRevision += 1
        let intent = playbackRevision
        replayTask?.cancel(); replayTask = nil
        if ended {
            let captured = generation
            replayTask = Task { @MainActor [weak self] in
                guard let self, await seek(to: 0) != nil, captured == generation,
                      intent == playbackRevision,!Task.isCancelled else { return }
                replayTask = nil
                player.playImmediately(atRate: baseRate)
            }
        } else { player.playImmediately(atRate: baseRate) }
    }
    func pause() {
        playbackRevision += 1
        replayTask?.cancel(); replayTask = nil
        player.pause()
    }
    func seek(to seconds: Double) async -> Double? {
        guard !Task.isCancelled, seconds.isFinite, let item = player.currentItem,
              item.duration.seconds.isFinite, item.duration.seconds > 0 else { return nil }
        let target = min(max(0, seconds), item.duration.seconds)
        let captured = generation
        seekRevision += 1
        let seekID = seekRevision
        item.cancelPendingSeeks()
        seeking = true
        sample()
        defer { if captured == generation && seekID == seekRevision { seeking = false; sample() } }
        let success = await player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        guard !Task.isCancelled, success, captured == generation, seekID == seekRevision,
              player.currentItem === item else { return nil }
        if target < item.duration.seconds { ended = false }
        let actual = player.currentTime().seconds
        return actual.isFinite ? actual : nil
    }
    @discardableResult func setRate(_ rate: Double) -> Bool {
        guard rate.isFinite, (0.25...3).contains(rate), let item = player.currentItem else { return false }
        if rate < 1 && !item.canPlaySlowForward { return false }
        if rate > 2 && !item.canPlayFastForward { return false }
        baseRate = Float(rate)
        if player.timeControlStatus != .paused { player.rate = baseRate }
        sample()
        return true
    }
    func hold(rate: Double) { if heldRate == nil { heldRate = baseRate }; _ = setRate(rate) }
    func release() { if let heldRate { baseRate = heldRate; if player.rate != 0 { player.rate = heldRate }; self.heldRate = nil } }
    func setZoom(_ scale: Double,anchorX:Double=0.5,anchorY:Double=0.5) {
        guard scale.isFinite,anchorX.isFinite,anchorY.isFinite else { return }
        zoom = CGFloat(min(8, max(1, scale)))
        let visible = layer.videoRect.isEmpty ? layer.bounds : layer.videoRect
        let maximumX=max(0,(visible.width*zoom-layer.bounds.width)/2)
        let maximumY=max(0,(visible.height*zoom-layer.bounds.height)/2)
        let x=(0.5-CGFloat(min(1,max(0,anchorX))))*layer.bounds.width*(zoom-1)
        let y=(0.5-CGFloat(min(1,max(0,anchorY))))*layer.bounds.height*(zoom-1)
        layer.setAffineTransform(CGAffineTransform(a:zoom,b:0,c:0,d:zoom,tx:min(maximumX,max(-maximumX,x)),ty:min(maximumY,max(-maximumY,y))))
    }
    func setQualityPreference(height: Int) {
        // A public AVFoundation preference, not a guaranteed rendition selection.
        maximumHeight = min(4320, max(0, height))
        player.currentItem?.preferredMaximumResolution = preferredResolution
    }
    private var preferredResolution:CGSize {
        maximumHeight > 0 ? CGSize(width:CGFloat(maximumHeight)*16/9,height:CGFloat(maximumHeight)):.zero
    }
    func setCaption(language: String?) {
        guard let item = player.currentItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else { return }
        let option = language.flatMap { language in group.options.first(where: { $0.extendedLanguageTag == language }) }
        item.select(option, in: group)
    }
    var captions: [(String, String)] {
        guard let group = player.currentItem?.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else { return [] }
        return group.options.compactMap { option in option.extendedLanguageTag.map { ($0, option.displayName) } }
    }
    func togglePiP() {
        guard let pipController else { return }
        if pipController.isPictureInPictureActive { pipController.stopPictureInPicture() }
        else if pipController.isPictureInPicturePossible { pipController.startPictureInPicture() }
    }
    func close() {
        pause()
        if pipController?.isPictureInPictureActive == true { pipController?.stopPictureInPicture() }
        player.replaceCurrentItem(with: nil)
        itemObservation = nil
        if let endedObserver { NotificationCenter.default.removeObserver(endedObserver); self.endedObserver = nil }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver); self.failureObserver = nil }
        generation += 1
        seekRevision += 1
        ended = false; seeking = false; errorMessage = nil
        heldRate = nil
        baseRate = 1
        setZoom(1)
    }
    private func sample() {
        var result = MediaSnapshot()
        result.title = title
        result.elementID = "native-\(generation)"
        result.position = max(0, player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0)
        let duration = player.currentItem?.duration.seconds ?? 0
        result.duration = duration.isFinite ? max(0, duration) : 0
        result.live = duration.isInfinite || player.currentItem?.duration.isIndefinite == true
        result.ended = ended
        result.seeking = seeking
        result.muted = player.isMuted
        result.playing = player.timeControlStatus == .playing
        result.ready = player.currentItem?.status == .readyToPlay
        result.seekable = result.duration > 0 && !(player.currentItem?.seekableTimeRanges.isEmpty ?? true)
        result.width = Double(player.currentItem?.presentationSize.width ?? 0)
        result.height = Double(player.currentItem?.presentationSize.height ?? 0)
        result.viewportRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        // A paused AVPlayer reports rate zero; retain the chosen resume rate in that case.
        let actualRate=Double(player.rate)
        result.rate = actualRate.isFinite && actualRate > 0 ? actualRate:Double(baseRate)
        result.pictureInPictureAvailable = pipController?.isPictureInPicturePossible == true
        result.inPictureInPicture = pipController?.isPictureInPictureActive == true
        if player.currentItem?.status == .failed { errorMessage = "Das direkte Video konnte nicht geladen werden. Prüfe den Link und das Medienformat." }
        onSample?(result)
    }
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) { onPiP?(true); sample() }
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) { onPiP?(false); sample() }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        errorMessage = "Picture-in-Picture konnte für dieses Video nicht gestartet werden."
        onPiP?(false); sample()
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                   restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        onPiP?(false)
        completionHandler(true)
    }
    func shutdown() {
        close()
        if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil }
        statusObservation = nil
    }
}

struct NativeMediaSurface: UIViewRepresentable {
    let playback: NativePlayback
    func makeUIView(context: Context) -> NativeVideoView { NativeVideoView(layer: playback.layer) }
    func updateUIView(_ view: NativeVideoView, context: Context) { view.setNeedsLayout() }
}
final class NativeVideoView: UIView {
    private let videoLayer: AVPlayerLayer
    init(layer: AVPlayerLayer) {
        videoLayer = layer
        super.init(frame: .zero)
        backgroundColor = .black
        clipsToBounds = true
        self.layer.addSublayer(layer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        videoLayer.bounds = bounds
        videoLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }
}

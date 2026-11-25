// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum PlayerPresentation: String, Codable, Sendable {
    case closed, expanded, mini, fullscreen, pictureInPicture
}

enum PlayerOrientation: Equatable, Sendable {
    case portrait, landscapeLeft, landscapeRight, inverted, unknown
    var isLandscape: Bool { self == .landscapeLeft || self == .landscapeRight }
}

enum PlayerPresentationEvent: Equatable, Sendable {
    case open(sourceID: String)
    case expand
    case minimize
    case close
    case toggleFullscreen
    case exitFullscreen
    case orientationChanged(PlayerOrientation)
    /// Call only after the system confirms entry, not when entry is requested.
    case didEnterPictureInPicture
    case didExitPictureInPicture(restoreInterface: Bool)
}

/// Sole presentation authority. The reducer never starts playback or creates a web view.
struct PlayerPresentationState: Equatable, Sendable {
    private(set) var mode: PlayerPresentation = .closed
    private(set) var sourceID: String?
    private(set) var orientation: PlayerOrientation = .portrait
    private(set) var manualFullscreenExitLatched = false
    private var beforePictureInPicture: PlayerPresentation = .expanded
    private var manualFullscreenEntry = false

    var isFullscreen: Bool { mode == .fullscreen }
    var isExpanded: Bool { mode == .expanded || mode == .fullscreen }
    var isVisible: Bool { mode != .closed }

    mutating func reduce(_ event: PlayerPresentationEvent) {
        switch event {
        case .open(let id):
            let changed = sourceID != id
            sourceID = id
            if changed { manualFullscreenExitLatched = false; manualFullscreenEntry = false }
            mode = orientation.isLandscape && !manualFullscreenExitLatched ? .fullscreen : .expanded
        case .expand:
            guard sourceID != nil, mode != .pictureInPicture else { return }
            mode = orientation.isLandscape && !manualFullscreenExitLatched ? .fullscreen : .expanded
        case .minimize:
            guard sourceID != nil, mode != .pictureInPicture else { return }
            mode = .mini; manualFullscreenEntry = false
        case .close:
            sourceID = nil; mode = .closed; manualFullscreenEntry = false; manualFullscreenExitLatched = false
            beforePictureInPicture = .expanded
        case .toggleFullscreen:
            guard isExpanded else { return }
            if mode == .fullscreen { exitFullscreen() }
            else { manualFullscreenExitLatched = false; manualFullscreenEntry = true; mode = .fullscreen }
        case .exitFullscreen:
            guard mode == .fullscreen else { return }; exitFullscreen()
        case .orientationChanged(let next):
            guard next != .inverted, next != .unknown else { return }
            let changedPosture = next.isLandscape != orientation.isLandscape
            orientation = next
            if changedPosture { manualFullscreenExitLatched = false; manualFullscreenEntry = false }
            guard isExpanded else { return }
            if next.isLandscape { mode = manualFullscreenExitLatched ? .expanded : .fullscreen }
            else if !manualFullscreenEntry { mode = .expanded }
        case .didEnterPictureInPicture:
            guard sourceID != nil, mode != .closed, mode != .pictureInPicture else { return }
            beforePictureInPicture = mode
            mode = .pictureInPicture
        case .didExitPictureInPicture(let restore):
            guard mode == .pictureInPicture, sourceID != nil else { return }
            if restore {
                if beforePictureInPicture == .mini { mode = .mini }
                else {
                    mode = (manualFullscreenEntry || orientation.isLandscape) && !manualFullscreenExitLatched ? .fullscreen : .expanded
                }
            } else {
                mode = .mini
            }
        }
    }

    private mutating func exitFullscreen() {
        mode = .expanded
        // Latch the user's exit even while the sensor keeps reporting landscape.
        manualFullscreenExitLatched = true
        manualFullscreenEntry = false
    }
}

enum MiniPlayerLayout {
    static func size(in available: CGSize, aspectRatio: CGFloat) -> CGSize {
        let aspect = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 16.0 / 9.0
        let widthLimit = max(1, min(196, available.width - 24))
        let heightLimit = max(1, min(196, available.height - 24))
        let width = min(widthLimit, heightLimit * aspect)
        return CGSize(width: width, height: width / aspect)
    }
}

enum PlayerGestureLimits {
    static let zoom = 1.0...8.0
    static let seekSteps = [5, 10, 15, 20, 30]
    static let holdRates = [1.5, 2.0, 2.5, 3.0]
    static let minimumBrightness = 0.02
    static let minimizeDistance = 64.0
    static let minimizeFlingDistance = 24.0
    static let minimizeFlingVelocity = 900.0
    static let transitionDuration = 0.18

    static func clampedZoom(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(zoom.upperBound, max(zoom.lowerBound, value))
    }
}

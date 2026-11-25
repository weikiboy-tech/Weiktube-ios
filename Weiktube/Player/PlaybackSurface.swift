// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import UIKit
import WebKit

struct PlaybackSurface: UIViewRepresentable {
    @ObservedObject var coordinator: PlayerCoordinator
    let logicalSize: CGSize
    let miniWidth: CGFloat
    func makeUIView(context: Context) -> PlaybackContainer { PlaybackContainer(coordinator: coordinator) }
    func updateUIView(_ view: PlaybackContainer, context: Context) {
        view.coordinator = coordinator
        view.logicalSize = logicalSize
        view.miniWidth = miniWidth
        view.showNative(coordinator.isNative)
        view.setNeedsLayout()
    }
}

/// A stable document viewport is scaled into the mini card; layout changes don't reload media.
@MainActor
final class PlaybackContainer: UIView, UIGestureRecognizerDelegate {
    weak var coordinator: PlayerCoordinator?
    var miniWidth: CGFloat = 196
    var logicalSize = CGSize(width: 390, height: 220)
    private weak var attached: UIView?
    private var nativeView: NativeVideoView?
    private var pinchStart = 1.0
    private var scale = 1.0
    private var panLocation = CGPoint.zero
    private var panStartHeight: CGFloat = 1
    private var previousTranslation: CGFloat = 0
    private var volumeShown = false
    private var singleFingerBlocked = false
    private let pinch = UIPinchGestureRecognizer()
    private let pan = UIPanGestureRecognizer()
    private let doubleTap = UITapGestureRecognizer()
    private let hold = UILongPressGestureRecognizer()

    init(coordinator: PlayerCoordinator) {
        self.coordinator = coordinator
        super.init(frame: .zero)
        backgroundColor = .black
        clipsToBounds = true
        isAccessibilityElement = false
        pinch.addTarget(self, action: #selector(pinched(_:)))
        pan.addTarget(self, action: #selector(panned(_:)))
        pan.maximumNumberOfTouches = 1
        doubleTap.numberOfTapsRequired = 2
        doubleTap.addTarget(self, action: #selector(tappedTwice(_:)))
        hold.minimumPressDuration = 0.45
        hold.allowableMovement = 12
        hold.addTarget(self, action: #selector(held(_:)))
        for gesture in [pinch, pan, doubleTap, hold] {
            gesture.delegate = self
            gesture.cancelsTouchesInView = true
            addGestureRecognizer(gesture)
        }
        doubleTap.require(toFail: pinch)
        coordinator.web.webView.scrollView.pinchGestureRecognizer?.isEnabled = false
        showNative(coordinator.isNative)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func showNative(_ native: Bool) {
        guard let coordinator else { return }
        let content: UIView
        if native {
            if nativeView == nil { nativeView = NativeVideoView(layer: coordinator.native.layer) }
            content = nativeView!
        } else { content = coordinator.web.webView }
        guard attached !== content else { return }
        attached?.removeFromSuperview()
        addSubview(content)
        attached = content
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let attached else { return }
        let width = max(1, logicalSize.width), height = max(1, logicalSize.height)
        let baseScale = min(bounds.width / width, bounds.height / height)
        let progress = min(1,max(0,(width - bounds.width) / max(1,width - miniWidth)))
        var mediaRect = coordinator?.snapshot.viewportRect ?? .zero
        if coordinator?.isNative == true || mediaRect.isEmpty {
            let aspect = coordinator?.aspect ?? (16/9)
            let mediaWidth = min(width,height * aspect), mediaHeight = min(height,width / aspect)
            mediaRect = CGRect(x:(width-mediaWidth)/2/width,y:(height-mediaHeight)/2/height,width:mediaWidth/width,height:mediaHeight/height)
        }
        let cropScale = min(bounds.width / max(1,mediaRect.width * width),bounds.height / max(1,mediaRect.height * height))
        let factor = baseScale + (cropScale - baseScale) * progress
        let offsetX = (mediaRect.midX - 0.5) * width * factor * progress
        let offsetY = (mediaRect.midY - 0.5) * height * factor * progress
        attached.transform = .identity
        attached.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        attached.center = CGPoint(x: bounds.midX-offsetX, y: bounds.midY-offsetY)
        attached.transform = CGAffineTransform(scaleX: factor, y: factor)
    }
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard [pinch, pan, doubleTap, hold].contains(gestureRecognizer) else { return super.gestureRecognizerShouldBegin(gestureRecognizer) }
        guard let coordinator, !coordinator.isMini, !coordinator.isPiP else { return false }
        guard !UIAccessibility.isVoiceOverRunning else { return false }
        let point = gestureRecognizer.location(in: self)
        guard point.x > 18, point.x < bounds.width - 18, point.y > 16, point.y < bounds.height - 30 else { return false }
        if !coordinator.isNative {
            let normalized=CGPoint(x:point.x/max(1,bounds.width),y:point.y/max(1,bounds.height))
            guard !coordinator.snapshot.controlRects.contains(where:{$0.contains(normalized)}) else{return false}
        }
        if !coordinator.isNative && coordinator.originalControls && !coordinator.isFullscreen {
            let rect = coordinator.snapshot.viewportRect
            let normalized = CGPoint(x:point.x/max(1,bounds.width),y:point.y/max(1,bounds.height))
            guard rect.width > 0, rect.height > 0, rect.contains(normalized),
                  normalized.y < rect.maxY - 0.08 else { return false }
        }
        if gestureRecognizer === pinch { return true }
        if singleFingerBlocked { return false }
        if gestureRecognizer === pan {
            let velocity = pan.velocity(in: self)
            guard abs(velocity.y) > abs(velocity.x) * 1.25 else { return false }
            if coordinator.isFullscreen {
                return point.x < bounds.midX ? coordinator.settings.brightnessGesture : coordinator.settings.volumeGesture
            }
            return velocity.y > 0
        }
        if gestureRecognizer === doubleTap { return coordinator.settings.doubleTapSeek }
        if gestureRecognizer === hold { return coordinator.settings.holdToSpeed && coordinator.isFullscreen }
        return true
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if touch.phase == .began, pinch.numberOfTouches == 0, pinch.state != .began, pinch.state != .changed { singleFingerBlocked = false }
        return true
    }
    @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
        guard let coordinator else { return }
        if gesture.state == .began { coordinator.hold(false); pinchStart = coordinator.currentZoom; singleFingerBlocked = true }
        if gesture.state == .changed || gesture.state == .ended {
            scale = min(8, max(1, pinchStart * gesture.scale))
            let point=gesture.location(in:self), rect=coordinator.snapshot.viewportRect
            let x=rect.width>0 ? (point.x/max(1,bounds.width)-rect.minX)/rect.width:0.5
            let y=rect.height>0 ? (point.y/max(1,bounds.height)-rect.minY)/rect.height:0.5
            coordinator.setZoom(scale,anchorX:Double(min(1,max(0,x))),anchorY:Double(min(1,max(0,y))))
        }
    }
    @objc private func tappedTwice(_ gesture: UITapGestureRecognizer) {
        coordinator?.skipGesture(direction: gesture.location(in: self).x < bounds.midX ? -1 : 1)
    }
    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { coordinator?.hold(true) }
        if [.ended,.cancelled,.failed].contains(gesture.state) { coordinator?.hold(false) }
    }
    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        guard let coordinator else { return }
        if gesture.state == .began {
            panLocation = gesture.location(in: self); previousTranslation = 0; volumeShown = false
            panStartHeight = max(1, bounds.height)
            coordinator.hold(false)
        }
        let translation = gesture.translation(in: window).y
        if gesture.state == .changed {
            if coordinator.isFullscreen {
                if panLocation.x < bounds.midX {
                    coordinator.changeBrightness(delta: Double((previousTranslation - translation) / max(1,bounds.height)))
                } else if !volumeShown {
                    volumeShown = true; coordinator.showVolume = true
                    coordinator.showFeedback("Lautstärke mit dem Systemregler anpassen")
                }
            } else { coordinator.dragFraction = min(1,max(0,translation / panStartHeight)) }
            previousTranslation = translation
        }
        if [.ended,.cancelled,.failed].contains(gesture.state) {
            if !coordinator.isFullscreen {
                let finish = gesture.state == .ended && (Double(translation) >= PlayerGestureLimits.minimizeDistance ||
                    (Double(translation) >= PlayerGestureLimits.minimizeFlingDistance && Double(gesture.velocity(in:window).y) >= PlayerGestureLimits.minimizeFlingVelocity))
                withAnimation(.easeInOut(duration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.18)) {
                    if finish { coordinator.minimize() } else { coordinator.dragFraction = 0 }
                }
            }
            coordinator.endGesture()
        }
    }
}

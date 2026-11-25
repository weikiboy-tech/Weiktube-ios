// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import UIKit

/// A cancelled native touch sequence has a separate callback and never commits a seek.
@MainActor
struct SeekTimeline: View {
    @Binding var value: Double
    let duration: Double
    var identity = ""
    var enabled = true
    var onEditingChanged: (Bool) -> Void
    var onEditingCancelled: () -> Void = {}
    private var safeDuration: Double { duration.isFinite && duration > 0 ? duration : 1 }
    private var canEdit: Bool { enabled && duration.isFinite && duration > 0 }

    var body: some View {
        NativeSeekTimeline(value: $value, duration: safeDuration, identity: identity, enabled: canEdit,
                           onEditingChanged: onEditingChanged, onEditingCancelled: onEditingCancelled)
            .frame(height: 44).opacity(canEdit ? 1 : 0.45)
            .focusable(canEdit)
            .onKeyPress(.leftArrow) { keyboardSeek(value - 5) }
            .onKeyPress(.rightArrow) { keyboardSeek(value + 5) }
            .onKeyPress(.home) { keyboardSeek(0) }
            .onKeyPress(.end) { keyboardSeek(safeDuration) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Wiedergabeposition")
            .accessibilityValue("\(PlaybackTimeFormatter.string(value)) von \(PlaybackTimeFormatter.string(duration))")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: _ = keyboardSeek(value + 5)
                case .decrement: _ = keyboardSeek(value - 5)
                @unknown default: break
                }
            }
    }

    private func keyboardSeek(_ target: Double) -> KeyPress.Result {
        guard canEdit, target.isFinite else { return .ignored }
        onEditingChanged(true)
        value = min(safeDuration, max(0, target))
        onEditingChanged(false)
        return .handled
    }
}

@MainActor
private struct NativeSeekTimeline: UIViewRepresentable {
    @Binding var value: Double
    let duration: Double
    let identity: String
    let enabled: Bool
    let onEditingChanged: (Bool) -> Void
    let onEditingCancelled: () -> Void

    func makeUIView(context: Context) -> SeekTimelineControl {
        let control = SeekTimelineControl()
        updateUIView(control, context: context)
        return control
    }

    func updateUIView(_ control: SeekTimelineControl, context: Context) {
        control.onBegin = { onEditingChanged(true) }
        control.onChange = { value = $0 }
        control.onCommit = { onEditingChanged(false) }
        control.onCancel = onEditingCancelled
        control.configure(value: value, duration: duration, identity: identity, enabled: enabled)
    }

    static func dismantleUIView(_ control: SeekTimelineControl, coordinator: ()) { control.tearDown() }
}

@MainActor
private final class SeekTimelineControl: UIControl {
    var onBegin: (() -> Void)?
    var onChange: ((Double) -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    private let track = CALayer(), fill = CALayer(), thumb = CALayer()
    private var position = 0.0, duration = 1.0
    private var sourceIdentity = ""
    private var editing = false
    private weak var editingTouch: UITouch?
    private var editingFrame = CGRect.zero
    private var blockedSequence = false
    private weak var observedWindow: UIWindow?
    private var notifications: [NSObjectProtocol] = []
    private lazy var additionalTouchObserver = TimelineTouchObserver { [weak self] count in
        guard let self else { return }
        if count > 1 { blockedSequence = true; cancelEditing(deferred: false) }
        else if count == 0 { blockedSequence = false }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isAccessibilityElement = false
        track.backgroundColor = UIColor.white.withAlphaComponent(0.25).cgColor
        fill.backgroundColor = UIColor(Color.weiktubeRed).cgColor
        thumb.backgroundColor = UIColor(Color.weiktubeRed).cgColor
        for shape in [track, fill, thumb] { layer.addSublayer(shape) }
        for name in [UIDevice.orientationDidChangeNotification, UIApplication.willResignActiveNotification] {
            notifications.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.cancelEditing(deferred: false) }
            })
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(value: Double, duration: Double, identity: String, enabled: Bool) {
        if editing && (!enabled || identity != sourceIdentity || duration != self.duration) { cancelEditing(deferred: true) }
        sourceIdentity = identity
        self.duration = duration
        isEnabled = enabled
        if !editing { position = value.isFinite ? min(duration, max(0, value)) : 0 }
        setNeedsLayout()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if observedWindow !== window {
            cancelEditing(deferred: true)
            observedWindow?.removeGestureRecognizer(additionalTouchObserver)
            observedWindow = window
            window?.addGestureRecognizer(additionalTouchObserver)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if editing && !sameGeometry { cancelEditing(deferred: true) }
        let length = max(0, bounds.width - 16)
        let fraction = duration > 0 ? min(1, max(0, position / duration)) : 0
        let radius: CGFloat = editing ? 8 : 6
        CATransaction.begin(); CATransaction.setDisableActions(true)
        track.frame = CGRect(x: 8, y: bounds.midY - 2, width: length, height: 4)
        fill.frame = CGRect(x: 8, y: bounds.midY - 2, width: length * fraction, height: 4)
        track.cornerRadius = 2; fill.cornerRadius = 2
        thumb.frame = CGRect(x: 8 + length * fraction - radius, y: bounds.midY - radius, width: radius * 2, height: radius * 2)
        thumb.cornerRadius = radius
        CATransaction.commit()
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard isEnabled, !editing, !blockedSequence, touchCount(event) <= 1, bounds.width > 16 else { return false }
        editing = true; editingTouch = touch; editingFrame = convert(bounds, to: window)
        onBegin?()
        changePosition(touch)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard editing, editingTouch === touch, touchCount(event) <= 1, sameGeometry, isEnabled else {
            cancelEditing(deferred: false); return false
        }
        changePosition(touch)
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        defer { super.endTracking(touch, with: event) }
        guard editing else { return }
        guard let touch, editingTouch === touch, touchCount(event) <= 1, sameGeometry, isEnabled, !blockedSequence else {
            cancelEditing(deferred: false); return
        }
        changePosition(touch)
        editing = false; editingTouch = nil; setNeedsLayout()
        onCommit?()
    }

    override func cancelTracking(with event: UIEvent?) {
        cancelEditing(deferred: false)
        super.cancelTracking(with: event)
    }

    private var sameGeometry: Bool {
        guard window != nil else { return false }
        let current = convert(bounds, to: window)
        return abs(current.minX - editingFrame.minX) < 0.5 && abs(current.minY - editingFrame.minY) < 0.5 &&
            abs(current.width - editingFrame.width) < 0.5 && abs(current.height - editingFrame.height) < 0.5
    }

    private func touchCount(_ event: UIEvent?) -> Int {
        event?.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled }.count ?? 1
    }

    private func changePosition(_ touch: UITouch) {
        position = Double(min(1, max(0, (touch.location(in: self).x - 8) / max(1, bounds.width - 16)))) * duration
        onChange?(position)
        setNeedsLayout()
    }

    private func cancelEditing(deferred: Bool) {
        guard editing else { return }
        editing = false; editingTouch = nil; setNeedsLayout()
        let callback = onCancel
        // Identity/layout changes run inside SwiftUI updates; deliver state cancellation afterward.
        if deferred { DispatchQueue.main.async { callback?() } }
        else { callback?() }
    }

    func tearDown() {
        cancelEditing(deferred: true)
        observedWindow?.removeGestureRecognizer(additionalTouchObserver)
        observedWindow = nil
        for observer in notifications { NotificationCenter.default.removeObserver(observer) }
        notifications.removeAll()
        onBegin = nil; onChange = nil; onCommit = nil; onCancel = nil
    }
}

/// Observes a second finger even outside the timeline without preventing other gestures or touches.
@MainActor
private final class TimelineTouchObserver: UIGestureRecognizer {
    private let changed: (Int) -> Void
    init(changed: @escaping (Int) -> Void) {
        self.changed = changed
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false; delaysTouchesBegan = false; delaysTouchesEnded = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) { observe(event) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) { observe(event) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { observe(event) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { observe(event) }
    private func observe(_ event: UIEvent) {
        let count = event.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled }.count ?? 0
        changed(count)
        if count == 0 { state = .failed }
    }
}

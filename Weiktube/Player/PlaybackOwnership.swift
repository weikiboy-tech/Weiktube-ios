// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Serial reconciliation with revocation before grant. Old async completions never grant a stale owner.
@MainActor
final class PlaybackOwnership {
    enum Owner: Equatable { case none, home, shorts, player, pictureInPicture }
    private struct Selection: Equatable {
        let owner: Owner
        let nativePlayer: Bool
    }
    private var revision = 0
    private var desired: Selection?
    private var transition: Task<Void, Never>?
    let home: WebSession
    let shorts: WebSession
    let player: WebSession
    var pauseNative: (() -> Void)?
    init(home: WebSession, shorts: WebSession, player: WebSession) {
        self.home = home; self.shorts = shorts; self.player = player
    }
    func select(_ owner: Owner, nativePlayer: Bool = false) {
        let selection = Selection(owner: owner, nativePlayer: nativePlayer)
        guard selection != desired else { return }
        desired = selection
        revision += 1
        let captured = revision
        let previous = transition
        if !nativePlayer || (owner != .player && owner != .pictureInPicture) { pauseNative?() }
        // Cancellation cannot undo an already dispatched WebKit suspension change.
        // A new transition waits for the old one, revokes every competing surface,
        // then grants its owner. Older tasks never grant after the revision changes.
        transition = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            guard captured == revision else { return }
            if owner != .home { await home.setSuspended(true) }
            guard captured == revision else { return }
            if owner != .shorts { await shorts.setSuspended(true) }
            guard captured == revision else { return }
            if nativePlayer || (owner != .player && owner != .pictureInPicture) { await player.setSuspended(true) }
            guard captured == revision else { return }
            switch owner {
            case .home: await home.setSuspended(false)
            case .shorts: await shorts.setSuspended(false)
            case .player, .pictureInPicture: if !nativePlayer { await player.setSuspended(false) }
            case .none: break
            }
            guard captured == revision else { return }
            DiagnosticsStore.shared.record(.playbackOwnershipChanged)
        }
    }

    /// Used before starting a different native playback source.
    func waitForTransition() async {
        while true {
            let captured = revision
            await transition?.value
            if captured == revision { return }
        }
    }
}

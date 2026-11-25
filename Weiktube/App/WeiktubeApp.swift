// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

@main
struct WeiktubeApp:App {
    @StateObject private var model=AppModel()
    var body:some Scene {
        WindowGroup {RootView(app:model)}
    }
}

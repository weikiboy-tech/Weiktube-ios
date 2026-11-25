// SPDX-License-Identifier: GPL-3.0-only
import AppIntents
import Foundation

struct OpenWeiktubeIntent:AppIntent {
    static let title:LocalizedStringResource="In Weiktube öffnen"
    static let description: IntentDescription? = IntentDescription("Öffnet einen YouTube-Link oder ein unterstütztes öffentliches HTTPS-Video in Weiktube.")
    static let openAppWhenRun=true
    @Parameter(title:"Video-Link") var url:URL
    func perform() async throws -> some IntentResult {
        guard let route=YouTubeLinkRouter.route(url) else {throw WeiktubeIntentError.unsupportedLink}
        let inbox=try SharedLinkInbox.configured()
        try await inbox.enqueue(route.url)
        await MainActor.run {NotificationCenter.default.post(name:.weiktubeImportQueued,object:nil)}
        return .result()
    }
}
struct WeiktubeShortcuts:AppShortcutsProvider {
    static var appShortcuts:[AppShortcut] {
        AppShortcut(intent:OpenWeiktubeIntent(),phrases:["Video mit \(.applicationName) öffnen"],shortTitle:"In Weiktube öffnen",systemImageName:"play.rectangle")
    }
}
enum WeiktubeIntentError:Error,LocalizedError {
    case unsupportedLink
    var errorDescription:String?{"Dieser Link wird von Weiktube nicht unterstützt."}
}
extension Notification.Name {
    static let weiktubeImportQueued=Notification.Name("com.weiktube.ios.import-queued")
}

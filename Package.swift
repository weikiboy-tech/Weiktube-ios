// swift-tools-version: 5.9
import PackageDescription

// Foundation-only rules can run without UIKit, WebKit, a simulator, or account credentials.
let package = Package(
    name: "WeiktubeCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "WeiktubeCore", targets: ["WeiktubeCore"])],
    targets: [
        .target(name: "WeiktubeCore", path: "Weiktube", sources: [
            "Core/PlayerPresentationState.swift",
            "Core/ReleaseMetadata.swift",
            "Navigation/YouTubeLinkRouter.swift",
            "Persistence/AtomicJSONFile.swift",
            "Persistence/SharedLinkInbox.swift",
            "Persistence/PlaybackRestorationStore.swift"
        ]),
        .testTarget(name: "WeiktubeCoreTests", dependencies: ["WeiktubeCore"], path: "WeiktubeTests", sources: [
            "YouTubeLinkRouterTests.swift", "PlayerPresentationTests.swift", "SharedLinkInboxTests.swift", "AtomicJSONFileTests.swift", "PlaybackRestorationTests.swift", "ReleaseMetadataTests.swift"
        ])
    ]
)

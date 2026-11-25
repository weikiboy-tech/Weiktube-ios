// SPDX-License-Identifier: GPL-3.0-only
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

struct SharedLinkItem: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let url: URL
    let createdAt: Date
}

private struct SharedLinkDocument: Codable {
    var version = 1
    var items: [SharedLinkItem] = []
}

/// An app-group inbox. The extension queues public links; it never forces the main app to open.
/// Actor isolation serializes one process. A POSIX lock serializes app and extension processes.
actor SharedLinkInbox {
    static let maximumItems = 20
    static let configurationKey = "WeiktubeAppGroup"
    private let directory: URL
    private let now: @Sendable () -> Date

    init(containerURL: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = containerURL.appendingPathComponent("SharedLinks", isDirectory: true)
        self.now = now
    }

    static func configured(bundle: Bundle = .main) throws -> SharedLinkInbox {
        guard let identifier = bundle.object(forInfoDictionaryKey: configurationKey) as? String,
              identifier.hasPrefix("group."), !identifier.contains("$("), !identifier.contains("YOUR_") else {
            throw LocalStorageError.appGroupUnavailable
        }
        #if os(iOS) || os(macOS)
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            throw LocalStorageError.appGroupUnavailable
        }
        return SharedLinkInbox(containerURL: root)
        #else
        throw LocalStorageError.appGroupUnavailable
        #endif
    }

    @discardableResult
    func enqueue(_ url: URL) async throws -> SharedLinkItem {
        guard let route = YouTubeLinkRouter.route(url) else { throw LocalStorageError.invalidSharedLink }
        let canonical = route.url
        return try await withLockedDocument { document in
            // Repeated extension delivery of the same route does not launch duplicate playback.
            if let existing = document.items.first(where: { $0.url == canonical }) { return existing }
            let item = SharedLinkItem(id: UUID(), url: canonical, createdAt: now())
            document.items.append(item)
            document.items = Array(document.items.suffix(Self.maximumItems))
            return item
        }
    }

    @discardableResult
    func enqueue(_ text: String) async throws -> SharedLinkItem {
        guard let route = YouTubeLinkRouter.extractFirstRoute(from: text) else { throw LocalStorageError.invalidSharedLink }
        return try await enqueue(route.url)
    }

    func pending() async throws -> [SharedLinkItem] {
        try await withLockedDocument { $0.items }
    }

    /// Acknowledge only after routing succeeds. A crash before acknowledgment leaves the item pending.
    func acknowledge(_ ids: Set<UUID>) async throws {
        try await withLockedDocument { document in document.items.removeAll { ids.contains($0.id) } }
    }

    /// Convenience for atomic consume. Interactive import should prefer pending + acknowledge.
    func drain() async throws -> [URL] {
        try await withLockedDocument { document in
            let urls = document.items.map(\.url)
            document.items.removeAll()
            return urls
        }
    }

    func clear() async throws { try await withLockedDocument { $0.items.removeAll() } }

    private enum LockError: Error { case busy }

    private func withLockedDocument<T>(_ operation: (inout SharedLinkDocument) throws -> T) async throws -> T {
        // Short asynchronous retries cover simultaneous app/extension delivery without blocking a thread.
        // A suspended extension must never make the app wait indefinitely.
        for attempt in 0..<20 {
            do { return try withExclusiveLock(operation) }
            catch LockError.busy {
                guard attempt < 19 else { throw LocalStorageError.unavailable }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
        }
        throw LocalStorageError.unavailable
    }

    private func withExclusiveLock<T>(_ operation: (inout SharedLinkDocument) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lockURL = directory.appendingPathComponent("inbox.lock")
        #if canImport(Darwin) || canImport(Glibc)
        let descriptor = lockURL.path.withCString { open($0, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR) }
        guard descriptor >= 0 else { throw LocalStorageError.unavailable }
        defer { _ = close(descriptor) }
        // Nonblocking acquisition avoids waiting indefinitely if an extension is suspended while holding a lock.
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw LockError.busy }
        defer { _ = flock(descriptor, LOCK_UN) }
        #endif
        let storage = AtomicJSONFile<SharedLinkDocument>(url: directory.appendingPathComponent("inbox-v1.json"), maximumBytes: 196_608)
        var document = try storage.read() ?? SharedLinkDocument()
        guard document.version == 1 else { throw LocalStorageError.invalidVersion }
        let oldest = now().addingTimeInterval(-7 * 24 * 60 * 60)
        document.items = Array(document.items.filter { item in
            item.createdAt >= oldest && item.createdAt <= now().addingTimeInterval(60) && YouTubeLinkRouter.route(item.url) != nil
        }.suffix(Self.maximumItems))
        let result = try operation(&document)
        try storage.write(document)
        return result
    }
}

// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum PublicServiceError: Error { case invalidURL, invalidResponse, responseTooLarge, httpStatus(Int) }

struct PublicServiceResponse: Sendable {
    let status: Int
    let data: Data
    let retryAfter: String?
}

/// Public read-only services never inherit the browser's cookies, Keychain or OAuth authorization.
final class PublicServiceTransport: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let allowedHosts: Set<String>
    private let allowRedirects: Bool
    private let redirectLock = NSLock()
    private var redirectCounts: [Int: Int] = [:]
    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil; c.httpShouldSetCookies = false
        c.urlCredentialStorage = nil; c.urlCache = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = 10; c.timeoutIntervalForResource = 20
        return URLSession(configuration: c, delegate: self, delegateQueue: nil)
    }()
    init(hosts: Set<String>, allowRedirects: Bool = false) {
        self.allowedHosts = hosts; self.allowRedirects = allowRedirects
    }
    func trusted(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil && (url.port == nil || url.port == 443) && allowedHosts.contains(url.host?.lowercased() ?? "")
    }
    func get(_ url: URL, limit: Int, userAgent: String) async throws -> PublicServiceResponse {
        guard trusted(url), limit > 0 else { throw PublicServiceError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("application/json,application/octet-stream,text/plain", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        // A rejected header/body must also stop the underlying transfer.
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse, let finalURL = http.url, trusted(finalURL) else { throw PublicServiceError.invalidResponse }
        guard http.expectedContentLength <= limit else { throw PublicServiceError.responseTooLarge }
        var data = Data(); data.reserveCapacity(min(limit, 65536))
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < limit else { throw PublicServiceError.responseTooLarge }
            data.append(byte)
        }
        return .init(status: http.statusCode, data: data, retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        redirectLock.lock()
        let count = (redirectCounts[task.taskIdentifier] ?? 0) + 1
        redirectCounts[task.taskIdentifier] = count
        redirectLock.unlock()
        guard allowRedirects, count <= 5,
              let url = request.url, trusted(url) else { completionHandler(nil); return }
        completionHandler(request)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        redirectLock.lock(); redirectCounts.removeValue(forKey: task.taskIdentifier); redirectLock.unlock()
    }
    static func retryDelay(_ header: String?, now: Date) -> TimeInterval {
        if let number = header.flatMap(TimeInterval.init), number.isFinite { return min(31_536_000, max(60, number)) }
        let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(secondsFromGMT: 0); format.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return min(31_536_000, max(60, header.flatMap(format.date(from:))?.timeIntervalSince(now) ?? 60))
    }
}

/// The enclosing service actor serializes reads and atomic writes. Limits bound persistent public-data storage.
struct PublicServiceCache<Value: Codable> {
    struct Entry: Codable { var value: Value; var expires: Date; var used: Date }
    private var entries: [String: Entry] = [:]
    private let url: URL?
    let limit: Int
    init(name: String, limit: Int) {
        self.limit = limit
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("WeiktubePublicData", isDirectory: true)
        if let directory { try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        self.url = directory?.appendingPathComponent(name + ".json")
        if let url, let data = try? Data(contentsOf: url), data.count <= 16_777_216,
           let values = try? JSONDecoder().decode([String: Entry].self, from: data), values.count <= limit { entries = values }
    }
    mutating func value(for key: String, now: Date) -> Value? {
        guard var entry = entries[key], entry.expires > now else { return nil }
        entry.used = now; entries[key] = entry; return entry.value
    }
    mutating func insert(_ value: Value, for key: String, ttl: TimeInterval, now: Date) {
        entries[key] = .init(value: value, expires: now.addingTimeInterval(ttl), used: now)
        while entries.count > limit, let oldest = entries.min(by: { $0.value.used < $1.value.used })?.key { entries.removeValue(forKey: oldest) }
        save()
    }
    mutating func clear() { entries.removeAll(); save() }
    private func save() {
        guard let url, let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

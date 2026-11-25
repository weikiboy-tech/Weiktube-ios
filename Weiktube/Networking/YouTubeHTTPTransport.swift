// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// OAuth and Data API transport. Never follows redirects with bearer credentials.
final class YouTubeHTTPTransport: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = YouTubeHTTPTransport()
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 45
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    // The transport is initialized/accessed on the main actor; URLSession itself is thread safe.
    @MainActor
    func send(_ request: URLRequest, maximumBytes: Int = 2 * 1024 * 1024) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, url.scheme == "https",
              ["www.googleapis.com", "oauth2.googleapis.com"].contains(url.host ?? ""),
              url.user == nil, url.password == nil else { throw AccountError.invalidResponse }
        return try await Self.read(session: session, request: request, maximumBytes: maximumBytes)
    }

    // Parsing a bounded response happens on the generic executor, not the UI actor.
    private static func read(session: URLSession, request: URLRequest, maximumBytes: Int) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        let (stream, response) = try await session.bytes(for: request)
        defer {stream.task.cancel()}
        guard let http = response as? HTTPURLResponse else { throw AccountError.invalidResponse }
        guard http.expectedContentLength <= Int64(maximumBytes) else { throw AccountError.responseTooLarge }
        var data = Data()
        for try await byte in stream {
            if data.count >= maximumBytes { throw AccountError.responseTooLarge }
            data.append(byte)
            if data.count % 8192 == 0 { try Task.checkCancellation() }
        }
        return (data, http)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    static func formBody(_ values: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = values.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        // Query encoding leaves '+' unchanged, whereas form decoding interprets it as a space.
        return Data((components.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
    }
}

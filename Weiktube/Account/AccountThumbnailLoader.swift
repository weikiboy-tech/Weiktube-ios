// SPDX-License-Identifier: GPL-3.0-only
import CoreGraphics
import Foundation
import ImageIO

enum PublicThumbnailURLPolicy {
    static func allows(_ url:URL) -> Bool {
        guard url.absoluteString.utf8.count<=4096,!url.absoluteString.contains("\\"),
              let components=URLComponents(url:url,resolvingAgainstBaseURL:false),
              components.scheme?.lowercased()=="https",components.user==nil,components.password==nil,
              components.fragment==nil,components.port==nil || components.port==443,
              let host=components.host?.lowercased(),!host.hasSuffix(".") else{return false}
        return ["ytimg.com","ggpht.com","googleusercontent.com"].contains {host == $0 || host.hasSuffix("."+$0)}
    }
}

/// Immutable decoded pixels may cross executors; UIKit image construction remains on the UI actor.
final class PublicThumbnailBitmap: NSObject,@unchecked Sendable {
    let image:CGImage
    let cost:Int
    init(_ image:CGImage) {self.image=image;cost=image.bytesPerRow*image.height}
}

/// A separate public-image session never receives OAuth headers, cookies, or credential storage.
private final class ThumbnailSessionDelegate:NSObject,URLSessionTaskDelegate,@unchecked Sendable {
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,
                    newRequest request:URLRequest,completionHandler:@escaping (URLRequest?)->Void) {
        completionHandler(nil) // Redirects are validated and bounded explicitly by the loader.
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,didReceive challenge:URLAuthenticationChallenge,
                    completionHandler:@escaping (URLSession.AuthChallengeDisposition,URLCredential?)->Void) {
        completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust ? .performDefaultHandling:.cancelAuthenticationChallenge,nil)
    }
}

actor AccountThumbnailLoader {
    static let shared=AccountThumbnailLoader()
    private static let maximumBody=2*1024*1024
    private static let cacheLimit=8*1024*1024
    private let cache=NSCache<NSURL,PublicThumbnailBitmap>()
    // NSCache's cost limit is advisory. This ledger explicitly evicts before exceeding 8 MiB.
    private var costs:[URL:Int]=[:]
    private var recency:[URL]=[]
    private var totalCost=0
    private var active=0
    private var waitOrder:[UUID]=[]
    private var waiters:[UUID:CheckedContinuation<Bool,Never>]=[:]
    private let delegate=ThumbnailSessionDelegate()
    private lazy var session:URLSession = {
        let configuration=URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies=false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage=nil
        configuration.urlCredentialStorage=nil
        configuration.urlCache=nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest=8
        configuration.timeoutIntervalForResource=30
        configuration.httpMaximumConnectionsPerHost=3
        return URLSession(configuration:configuration,delegate:delegate,delegateQueue:nil)
    }()

    init() {cache.totalCostLimit=Self.cacheLimit;cache.countLimit=100}

    func load(_ url:URL) async -> PublicThumbnailBitmap? {
        guard PublicThumbnailURLPolicy.allows(url),!Task.isCancelled else{return nil}
        if let saved=cached(url) {return saved}
        guard await acquire() else{return nil}
        defer{release()}
        guard !Task.isCancelled else{return nil}
        if let saved=cached(url) {return saved}
        do {
            let data=try await download(url)
            try Task.checkCancellation()
            guard let bitmap=decode(data) else{return nil}
            try Task.checkCancellation()
            insert(bitmap,for:url)
            return bitmap
        } catch {return nil}
    }

    private func acquire() async -> Bool {
        guard !Task.isCancelled else{return false}
        if active<3 {active+=1;return true}
        let id=UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation {continuation in
                if Task.isCancelled {continuation.resume(returning:false)}
                else {waitOrder.append(id);waiters[id]=continuation}
            }
        } onCancel: {
            Task {await self.cancelWaiter(id)}
        }
    }
    private func cancelWaiter(_ id:UUID) {
        waitOrder.removeAll {$0==id}
        waiters.removeValue(forKey:id)?.resume(returning:false)
    }
    private func release() {
        while !waitOrder.isEmpty {
            if let waiter=waiters.removeValue(forKey:waitOrder.removeFirst()) {waiter.resume(returning:true);return}
        }
        active=max(0,active-1)
    }
    private func cached(_ url:URL) -> PublicThumbnailBitmap? {
        guard let image=cache.object(forKey:url as NSURL) else {
            if let cost=costs.removeValue(forKey:url) {totalCost-=cost;recency.removeAll {$0==url}}
            return nil
        }
        recency.removeAll {$0==url};recency.append(url)
        return image
    }
    private func insert(_ image:PublicThumbnailBitmap,for url:URL) {
        guard image.cost>0,image.cost<=Self.cacheLimit else{return}
        if let old=costs.removeValue(forKey:url) {totalCost-=old}
        recency.removeAll {$0==url}
        while totalCost+image.cost>Self.cacheLimit || recency.count>=100 {
            guard !recency.isEmpty else{break}
            let oldest=recency.removeFirst()
            if let cost=costs.removeValue(forKey:oldest) {totalCost-=cost}
            cache.removeObject(forKey:oldest as NSURL)
        }
        cache.setObject(image,forKey:url as NSURL,cost:image.cost)
        costs[url]=image.cost;totalCost+=image.cost;recency.append(url)
    }
    private enum ImageError:Error {case response,oversize,timeout}
    private func download(_ original:URL) async throws -> Data {
        var target=original
        let deadline=ContinuousClock.now.advanced(by:.seconds(30))
        for redirect in 0...3 {
            try Task.checkCancellation()
            guard ContinuousClock.now<deadline,PublicThumbnailURLPolicy.allows(target) else{throw ImageError.timeout}
            var request=URLRequest(url:target)
            request.setValue("image/*",forHTTPHeaderField:"Accept")
            request.setValue("identity",forHTTPHeaderField:"Accept-Encoding")
            let (stream,response)=try await session.bytes(for:request)
            defer {stream.task.cancel()}
            guard let http=response as? HTTPURLResponse else{throw ImageError.response}
            if [301,302,303,307,308].contains(http.statusCode) {
                guard redirect<3,let location=http.value(forHTTPHeaderField:"Location"),
                      let next=URL(string:location,relativeTo:target)?.absoluteURL,PublicThumbnailURLPolicy.allows(next) else{throw ImageError.response}
                target=next
                continue
            }
            guard http.statusCode==200,http.mimeType?.lowercased().hasPrefix("image/")==true else{throw ImageError.response}
            guard http.expectedContentLength<=Int64(Self.maximumBody) else{throw ImageError.oversize}
            var data=Data()
            for try await byte in stream {
                guard data.count<Self.maximumBody else{throw ImageError.oversize}
                data.append(byte)
                if data.count%8192==0 {
                    try Task.checkCancellation()
                    guard ContinuousClock.now<deadline else{throw ImageError.timeout}
                }
            }
            guard !data.isEmpty,ContinuousClock.now<deadline,
                  http.expectedContentLength<0 || http.expectedContentLength==data.count else{throw ImageError.response}
            return data
        }
        throw ImageError.response
    }
    private func decode(_ data:Data) -> PublicThumbnailBitmap? {
        guard let source=CGImageSourceCreateWithData(data as CFData,[kCGImageSourceShouldCache:false] as CFDictionary),
              CGImageSourceGetCount(source)>0,
              let properties=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
              let width=properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height=properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue.isFinite,height.doubleValue.isFinite,
              (1...8192).contains(width.intValue),(1...8192).contains(height.intValue),
              width.intValue*height.intValue<=25_000_000 else{return nil}
        let options:[CFString:Any]=[
            kCGImageSourceCreateThumbnailFromImageAlways:true,
            kCGImageSourceCreateThumbnailWithTransform:true,
            kCGImageSourceThumbnailMaxPixelSize:768,
            kCGImageSourceShouldCacheImmediately:true,
            kCGImageSourceShouldAllowFloat:false
        ]
        guard let image=CGImageSourceCreateThumbnailAtIndex(source,0,options as CFDictionary),
              image.width<=768,image.height<=768 else{return nil}
        return PublicThumbnailBitmap(image)
    }
}

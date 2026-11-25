// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CoreFoundation
import CoreGraphics

struct MediaSnapshot: Equatable {
    var videoID = ""
    var title = "Video"
    var position = 0.0
    var duration = 0.0
    var playing = false
    var ended = false
    var live = false
    var seeking = false
    var muted = false
    var width = 0.0
    var height = 0.0
    var rate = 1.0
    var ready = false
    var seekable = false
    var pictureInPictureAvailable = false
    var inPictureInPicture = false
    var autoplayBlocked = false
    var advertisement = false
    var elementID = ""
    var mediaEvent = "native"
    var readyState = 0
    var networkState = 0
    var mediaErrorCode = 0
    /// Visible portion of the video element, in 0...1 coordinates relative to its WebView.
    var viewportRect: CGRect = .zero
    var controlRects:[CGRect]=[]

    var progress: Double {
        guard position.isFinite, duration.isFinite, duration > 0 else { return 0 }
        return min(1, max(0, position / duration))
    }
    static func decode(_ object: [String: Any]) -> MediaSnapshot? {
        guard let kind = object["kind"] as? String, kind == "media",
              let videoID = object["videoID"] as? String,
              videoID.isEmpty || YouTubeLinkRouter.validVideoID(videoID),
              let elementID = object["elementID"] as? String, elementID.count <= 128 else { return nil }
        func number(_ key: String, fallback: Double = 0) -> Double {
            guard let value = object[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
                  value.doubleValue.isFinite else { return fallback }
            return value.doubleValue
        }
        func flag(_ key: String) -> Bool {
            guard let value = object[key] as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return false }
            return value.boolValue
        }
        var result = MediaSnapshot()
        result.videoID = videoID
        result.elementID = elementID
        let event=object["event"] as? String ?? "initial"
        let events:Set<String>=["initial","timeupdate","playing","pause","ended","loadedmetadata","loadeddata","canplay","durationchange","emptied","volumechange","ratechange","seeking","seeked","progress","error","webkitpresentationmodechanged"]
        result.mediaEvent=events.contains(event) ? event:"unknown"
        result.readyState=Int(min(4,max(0,number("readyState"))))
        result.networkState=Int(min(3,max(0,number("networkState"))))
        result.mediaErrorCode=Int(min(4,max(0,number("errorCode"))))
        result.title = String((object["title"] as? String ?? "Video").prefix(200))
        result.position = min(1_000_000_000, max(0, number("position")))
        result.duration = min(1_000_000_000, max(0, number("duration")))
        result.playing = flag("playing")
        result.ended = flag("ended")
        result.live = flag("live")
        result.seeking = flag("seeking")
        result.muted = flag("muted")
        result.width = min(32_768, max(0, number("width")))
        result.height = min(32_768, max(0, number("height")))
        result.rate = max(0.25, min(4, number("rate", fallback: 1)))
        result.ready = flag("ready")
        result.seekable = flag("seekable")
        result.pictureInPictureAvailable = flag("pipAvailable")
        result.inPictureInPicture = flag("pip")
        result.autoplayBlocked = flag("autoplayBlocked")
        result.advertisement = flag("advertisement")
        if let rectangles=object["controlRects"] as? [[String:Any]],rectangles.count<=64 {
            result.controlRects=rectangles.compactMap { rect in
                guard let x=rect["x"] as? Double,let y=rect["y"] as? Double,
                      let width=rect["width"] as? Double,let height=rect["height"] as? Double,
                      [x,y,width,height].allSatisfy({$0.isFinite && abs($0)<=100}),width>0,height>0 else{return nil}
                let bounded=CGRect(x:x,y:y,width:width,height:height).intersection(CGRect(x:0,y:0,width:1,height:1))
                return bounded.isEmpty || bounded.isNull ? nil:bounded
            }
        }
        if let rect = object["rect"] as? [String: Any], rect.count == 4 {
            func coordinate(_ key: String) -> Double? {
                guard let value = rect[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
                      value.doubleValue.isFinite, abs(value.doubleValue) <= 100 else { return nil }
                return value.doubleValue
            }
            if let x = coordinate("x"), let y = coordinate("y"),
               let width = coordinate("width"), let height = coordinate("height"), width >= 0, height >= 0 {
                let visible = CGRect(x: x, y: y, width: width, height: height)
                    .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
                result.viewportRect = visible.isNull || visible.isEmpty ? .zero : visible
            }
        }
        return result
    }
}

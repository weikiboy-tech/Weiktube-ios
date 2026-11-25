// SPDX-License-Identifier: GPL-3.0-only
import Combine
import Foundation

enum ReleaseCheckState:Equatable {
    case idle,cached,checking,updateAvailable,current,ahead,installedVersionUnknown,privateOrUnavailable
    case failed(String)
}

/// Read-only release metadata. This service has no repository or Google credentials and installs nothing.
@MainActor
final class ReleaseChecker:ObservableObject {
    static let endpoint=URL(string:"https://api.github.com/repos/weikiboy-tech/Weiktube-iOS/releases/latest")!
    let installedVersion:String
    @Published private(set) var state:ReleaseCheckState = .idle
    @Published private(set) var release:ReleaseMetadata?
    @Published private(set) var lastAttempt:Date?
    @Published private(set) var lastChecked:Date?
    private let defaults:UserDefaults
    private let transport=PublicServiceTransport(hosts:["api.github.com"],allowRedirects:false)
    private let cacheKey="weiktube.release-metadata.v1"
    private let attemptKey="weiktube.release-last-attempt.v1"
    private let outcomeKey="weiktube.release-last-outcome.v1"
    private let now:() -> Date
    private let fetch:(@MainActor (URL,Int,String) async throws -> PublicServiceResponse)?
    private static let maximumBytes=524_288
    private struct CachedRelease:Codable {let schema:Int;let value:ReleaseMetadata;let checkedAt:Date}

    var isChecking:Bool {state == .checking}

    init(defaults:UserDefaults = .standard,currentVersion:String?=nil,now:@escaping () -> Date = Date.init,
         fetch:(@MainActor (URL,Int,String) async throws -> PublicServiceResponse)?=nil) {
        self.defaults=defaults
        self.now=now;self.fetch=fetch
        installedVersion=String((currentVersion ?? (Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String) ?? "Unbekannt").prefix(100))
        let currentTime=now()
        if let date=defaults.object(forKey:attemptKey) as? Date,date.timeIntervalSince1970.isFinite,date<=currentTime.addingTimeInterval(60) {
            lastAttempt=date
        }
        if let data=defaults.data(forKey:cacheKey) {
            if data.count<=Self.maximumBytes,let cached=try? JSONDecoder().decode(CachedRelease.self,from:data),
               cached.schema==1,cached.value.isValid,cached.checkedAt.timeIntervalSince1970.isFinite,
               cached.checkedAt<=currentTime.addingTimeInterval(60),currentTime.timeIntervalSince(cached.checkedAt)<=30*24*60*60 {
                release=cached.value;lastChecked=cached.checkedAt;state = .cached
            } else {defaults.removeObject(forKey:cacheKey)}
        }
        if lastAttempt != nil {
            switch defaults.string(forKey:outcomeKey) {
            case "private":release=nil;lastChecked=nil;state = .privateOrUnavailable
            case "failed":state = .failed("Die letzte Prüfung hat keinen aktuellen Release-Stand bestätigt. Du kannst sie manuell wiederholen.")
            case "attempted":state = .failed("Die letzte Release-Prüfung wurde nicht abgeschlossen. Du kannst sie manuell wiederholen.")
            default:
                if release==nil {state = .failed("Eine frühere Prüfung ist vermerkt; es liegt kein gültiger gespeicherter Release-Stand vor.")}
            }
        }
    }

    func check(automatically:Bool=false) async {
        guard !isChecking,!Task.isCancelled else{return}
        let attemptedAt=now()
        if automatically,let lastAttempt,attemptedAt.timeIntervalSince(lastAttempt)<24*60*60 {return}
        lastAttempt=attemptedAt
        defaults.set(attemptedAt,forKey:attemptKey) // Failed attempts also participate in the daily limit.
        defaults.set("attempted",forKey:outcomeKey)
        state = .checking
        do {
            let safeVersion=ReleaseVersion(installedVersion)?.description ?? "development"
            let userAgent="Weiktube-iOS/\(safeVersion) release-metadata"
            let response:PublicServiceResponse
            if let fetch {response=try await fetch(Self.endpoint,Self.maximumBytes,userAgent)}
            else {response=try await transport.get(Self.endpoint,limit:Self.maximumBytes,userAgent:userAgent)}
            try Task.checkCancellation()
            switch response.status {
            case 200:
                let value=try ReleaseMetadata.decode(response.data)
                guard value.isValid,let newest=value.version else {throw PublicServiceError.invalidResponse}
                let checked=self.now()
                release=value;lastChecked=checked
                if let installed=ReleaseVersion(installedVersion) {
                    state = newest>installed ? .updateAvailable:(newest == installed ? .current:.ahead)
                } else {state = .installedVersionUnknown}
                let cached=CachedRelease(schema:1,value:value,checkedAt:checked)
                if let data=try? JSONEncoder().encode(cached),data.count<=Self.maximumBytes {defaults.set(data,forKey:cacheKey)}
                defaults.set("success",forKey:outcomeKey)
            case 404:
                release=nil;lastChecked=nil
                defaults.removeObject(forKey:cacheKey)
                defaults.set("private",forKey:outcomeKey)
                state = .privateOrUnavailable
            case 401:
                defaults.set("failed",forKey:outcomeKey)
                state = .failed("Das Release ist ohne Repository-Zugriff nicht abrufbar. Die Prüfung verwendet keine Anmeldedaten.")
            case 403,429:
                defaults.set("failed",forKey:outcomeKey)
                state = .failed("GitHub hat die öffentliche Prüfung begrenzt. Versuche es später erneut; es wird kein Update-Status angenommen.")
            default:
                defaults.set("failed",forKey:outcomeKey)
                state = .failed("GitHub konnte die Release-Informationen nicht bestätigen (HTTP \(response.status)).")
            }
        } catch is CancellationError {
            defaults.set("failed",forKey:outcomeKey)
            state = .failed("Die Prüfung wurde abgebrochen. Ein aktueller Release-Stand wurde nicht bestätigt.")
        } catch {
            defaults.set("failed",forKey:outcomeKey)
            state = .failed("Die Release-Informationen konnten nicht sicher geladen werden. Prüfe die Verbindung oder versuche es später erneut.")
        }
    }
}

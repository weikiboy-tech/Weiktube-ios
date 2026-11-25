// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Combine

enum AppAppearance: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { switch self { case .system: return "System"; case .light: return "Hell"; case .dark: return "Dunkel" } }
}

/// Preferences contain no account tokens or website data. SponsorBlock owns its own settings store.
@MainActor
final class AppSettings: ObservableObject {
    @Published var appearance: AppAppearance = .system { didSet { persist() } }
    @Published var adBlockEnabled = true { didSet { persist() } }
    @Published var filterAds = true { didSet { persist() } }
    @Published var filterTrackers = true { didSet { persist() } }
    @Published var customDomains = "" { didSet { persist() } }
    @Published var domainExceptions = "" { didSet { persist() } }
    @Published var saveHistory = true { didSet { persist() } }
    @Published var brightnessGesture = true { didSet { persist() } }
    @Published var volumeGesture = true { didSet { persist() } }
    @Published var doubleTapSeek = true { didSet { persist() } }
    @Published var seekSeconds = 10 { didSet { persist() } }
    @Published var holdToSpeed = true { didSet { persist() } }
    @Published var holdSpeed = 2.0 { didSet { persist() } }
    @Published var wifiQuality = 1080 { didSet { persist() } }
    @Published var mobileQuality = 720 { didSet { persist() } }
    @Published var returnYouTubeDislike = false { didSet { persist() } }
    @Published var automaticUpdateChecks = false { didSet { persist() } }
    @Published var automaticFilterUpdateChecks = true { didSet { persist() } }
    @Published private(set) var storageError: String?

    static let seekChoices = [5, 10, 15, 20, 30]
    static let holdChoices = [1.5, 2.0, 2.5, 3.0]
    static let qualityChoices = [0, 144, 240, 360, 480, 720, 1080, 1440, 2160]
    private let defaults: UserDefaults
    private let key: String
    private var restoring = false

    init(defaults: UserDefaults = .standard, key: String = "weiktube.settings.v1") {
        self.defaults = defaults; self.key = key
        if let data = defaults.data(forKey: key) {
            if data.count <= 1_048_576, let values = try? JSONDecoder().decode(SettingsValues.self, from: data) {
                apply(values)
            } else {
                storageError = "Die gespeicherten Einstellungen konnten nicht gelesen werden. Sichere Standardwerte sind aktiv."
            }
        }
    }

    func restoreDefaults() { apply(SettingsValues()); persist() }

    private func apply(_ values: SettingsValues) {
        restoring = true
        appearance = values.appearance
        adBlockEnabled = values.adBlockEnabled; filterAds = values.filterAds; filterTrackers = values.filterTrackers
        customDomains = values.customDomains; domainExceptions = values.domainExceptions
        saveHistory = values.saveHistory; brightnessGesture = values.brightnessGesture; volumeGesture = values.volumeGesture
        doubleTapSeek = values.doubleTapSeek; seekSeconds = Self.seekChoices.contains(values.seekSeconds) ? values.seekSeconds : 10
        holdToSpeed = values.holdToSpeed; holdSpeed = Self.holdChoices.contains(values.holdSpeed) ? values.holdSpeed : 2
        wifiQuality = Self.qualityChoices.contains(values.wifiQuality) ? values.wifiQuality : 1080
        mobileQuality = Self.qualityChoices.contains(values.mobileQuality) ? values.mobileQuality : 720
        returnYouTubeDislike = values.returnYouTubeDislike; automaticUpdateChecks = values.automaticUpdateChecks
        automaticFilterUpdateChecks = values.automaticFilterUpdateChecks
        restoring = false
    }

    private func persist() {
        guard !restoring else { return }
        do {
            let value = SettingsValues(appearance: appearance, adBlockEnabled: adBlockEnabled, filterAds: filterAds,
                                       filterTrackers: filterTrackers, customDomains: customDomains, domainExceptions: domainExceptions,
                                       saveHistory: saveHistory, brightnessGesture: brightnessGesture, volumeGesture: volumeGesture,
                                       doubleTapSeek: doubleTapSeek, seekSeconds: seekSeconds, holdToSpeed: holdToSpeed,
                                       holdSpeed: holdSpeed, wifiQuality: wifiQuality, mobileQuality: mobileQuality,
                                       returnYouTubeDislike: returnYouTubeDislike, automaticUpdateChecks: automaticUpdateChecks,
                                       automaticFilterUpdateChecks: automaticFilterUpdateChecks)
            let data = try JSONEncoder().encode(value)
            guard data.count <= 1_048_576 else { storageError = "Die Filterlisten sind zu groß, um sie zu speichern."; return }
            defaults.set(data, forKey: key)
            storageError = nil
        } catch { storageError = "Einstellungen konnten nicht gespeichert werden." }
    }
}

private struct SettingsValues: Codable {
    var appearance: AppAppearance = .system
    var adBlockEnabled = true
    var filterAds = true
    var filterTrackers = true
    var customDomains = ""
    var domainExceptions = ""
    var saveHistory = true
    var brightnessGesture = true
    var volumeGesture = true
    var doubleTapSeek = true
    var seekSeconds = 10
    var holdToSpeed = true
    var holdSpeed = 2.0
    var wifiQuality = 1080
    var mobileQuality = 720
    var returnYouTubeDislike = false
    var automaticUpdateChecks = false
    var automaticFilterUpdateChecks = true

    enum CodingKeys: String, CodingKey {
        case appearance, adBlockEnabled, filterAds, filterTrackers, customDomains, domainExceptions, saveHistory,
             brightnessGesture, volumeGesture, doubleTapSeek, seekSeconds, holdToSpeed, holdSpeed,
             wifiQuality, mobileQuality, returnYouTubeDislike, automaticUpdateChecks, automaticFilterUpdateChecks
    }

    init(appearance: AppAppearance = .system, adBlockEnabled: Bool = true, filterAds: Bool = true,
         filterTrackers: Bool = true, customDomains: String = "", domainExceptions: String = "", saveHistory: Bool = true,
         brightnessGesture: Bool = true, volumeGesture: Bool = true, doubleTapSeek: Bool = true, seekSeconds: Int = 10,
         holdToSpeed: Bool = true, holdSpeed: Double = 2, wifiQuality: Int = 1080, mobileQuality: Int = 720,
         returnYouTubeDislike: Bool = false, automaticUpdateChecks: Bool = false, automaticFilterUpdateChecks: Bool = true) {
        self.appearance = appearance; self.adBlockEnabled = adBlockEnabled; self.filterAds = filterAds; self.filterTrackers = filterTrackers
        self.customDomains = customDomains; self.domainExceptions = domainExceptions; self.saveHistory = saveHistory
        self.brightnessGesture = brightnessGesture; self.volumeGesture = volumeGesture; self.doubleTapSeek = doubleTapSeek
        self.seekSeconds = seekSeconds; self.holdToSpeed = holdToSpeed; self.holdSpeed = holdSpeed
        self.wifiQuality = wifiQuality; self.mobileQuality = mobileQuality; self.returnYouTubeDislike = returnYouTubeDislike
        self.automaticUpdateChecks = automaticUpdateChecks
        self.automaticFilterUpdateChecks = automaticFilterUpdateChecks
    }

    /// A new preference added in a later app update does not invalidate the existing user settings.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appearance = (try? c.decode(AppAppearance.self, forKey: .appearance)) ?? .system
        adBlockEnabled = (try? c.decode(Bool.self, forKey: .adBlockEnabled)) ?? true
        filterAds = (try? c.decode(Bool.self, forKey: .filterAds)) ?? true
        filterTrackers = (try? c.decode(Bool.self, forKey: .filterTrackers)) ?? true
        customDomains = String(((try? c.decode(String.self, forKey: .customDomains)) ?? "").prefix(262_144))
        domainExceptions = String(((try? c.decode(String.self, forKey: .domainExceptions)) ?? "").prefix(262_144))
        saveHistory = (try? c.decode(Bool.self, forKey: .saveHistory)) ?? true
        brightnessGesture = (try? c.decode(Bool.self, forKey: .brightnessGesture)) ?? true
        volumeGesture = (try? c.decode(Bool.self, forKey: .volumeGesture)) ?? true
        doubleTapSeek = (try? c.decode(Bool.self, forKey: .doubleTapSeek)) ?? true
        seekSeconds = (try? c.decode(Int.self, forKey: .seekSeconds)) ?? 10
        holdToSpeed = (try? c.decode(Bool.self, forKey: .holdToSpeed)) ?? true
        holdSpeed = (try? c.decode(Double.self, forKey: .holdSpeed)) ?? 2
        wifiQuality = (try? c.decode(Int.self, forKey: .wifiQuality)) ?? 1080
        mobileQuality = (try? c.decode(Int.self, forKey: .mobileQuality)) ?? 720
        returnYouTubeDislike = (try? c.decode(Bool.self, forKey: .returnYouTubeDislike)) ?? false
        automaticUpdateChecks = (try? c.decode(Bool.self, forKey: .automaticUpdateChecks)) ?? false
        automaticFilterUpdateChecks = (try? c.decode(Bool.self, forKey: .automaticFilterUpdateChecks)) ?? true
    }
}

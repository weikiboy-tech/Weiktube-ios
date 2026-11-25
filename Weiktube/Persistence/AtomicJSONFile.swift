// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum LocalStorageError: Error, LocalizedError {
    case unavailable, tooLarge, invalidVersion, invalidSharedLink, appGroupUnavailable
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Der lokale Speicher ist momentan nicht verfügbar."
        case .tooLarge: return "Die lokale Datendatei überschreitet die erlaubte Größe."
        case .invalidVersion: return "Die gespeicherte Datenversion wird nicht unterstützt."
        case .invalidSharedLink: return "Dieser Link kann nicht sicher an Weiktube übergeben werden."
        case .appGroupUnavailable: return "Die App-Gruppe ist für diese Signierung nicht verfügbar. Link kopieren und in Weiktube öffnen."
        }
    }
}

enum PersistencePaths {
    static func applicationSupportDirectory(fileManager: FileManager = .default) throws -> URL {
        guard let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw LocalStorageError.unavailable
        }
        let directory = root.appendingPathComponent("Weiktube", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

/// Caller owns serialization. Atomic replacement never leaves a partially written JSON file.
struct AtomicJSONFile<Value: Codable>: Sendable {
    let url: URL
    var maximumBytes = 1_048_576

    func read() throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let attributes = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = attributes.fileSize, size >= 0, size <= maximumBytes else { throw LocalStorageError.tooLarge }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= maximumBytes else { throw LocalStorageError.tooLarge }
        return try JSONDecoder().decode(Value.self, from: data)
    }

    func write(_ value: Value) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        guard data.count <= maximumBytes else { throw LocalStorageError.tooLarge }
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}

// SPDX-License-Identifier: GPL-3.0-only
import XCTest
#if SWIFT_PACKAGE
@testable import WeiktubeCore
#else
@testable import Weiktube
#endif

final class AtomicJSONFileTests: XCTestCase {
    private struct Payload: Codable, Equatable { let value: String }

    private func temporaryFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WeiktubeAtomicTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("data.json")
    }

    func testAtomicReplacementAndRestartRead() throws {
        let file = AtomicJSONFile<Payload>(url: try temporaryFile())
        XCTAssertNil(try file.read())
        try file.write(Payload(value: "first"))
        try file.write(Payload(value: "replacement"))
        XCTAssertEqual(try AtomicJSONFile<Payload>(url: file.url).read(), Payload(value: "replacement"))
    }

    func testOversizeWriteCannotClobberPreviouslySavedData() throws {
        let file = AtomicJSONFile<Payload>(url: try temporaryFile(), maximumBytes: 64)
        try file.write(Payload(value: "retained"))
        XCTAssertThrowsError(try file.write(Payload(value: String(repeating: "x", count: 100))))
        XCTAssertEqual(try file.read(), Payload(value: "retained"))
    }

    func testReadRejectsOversizeFileBeforeDecoding() throws {
        let file = AtomicJSONFile<Payload>(url: try temporaryFile(), maximumBytes: 64)
        try FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 65, count: 65).write(to: file.url)
        XCTAssertThrowsError(try file.read()) { error in
            guard case LocalStorageError.tooLarge = error else { return XCTFail("Expected size boundary") }
        }
    }
}

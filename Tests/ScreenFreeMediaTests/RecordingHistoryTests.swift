import Foundation
import XCTest
@testable import ScreenFree

final class RecordingHistoryTests: XCTestCase {
    func testCatalogFindsMoviesNewestFirstAndIgnoresOtherFiles() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent(
            "ScreenFree-History-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: directory) }

        let older = directory.appendingPathComponent("Recording-older.mp4")
        let newer = directory.appendingPathComponent("Merged-newer.mov")
        let ignored = directory.appendingPathComponent("notes.txt")
        try Data([0x01]).write(to: older)
        try Data([0x02, 0x03]).write(to: newer)
        try Data([0x04]).write(to: ignored)
        try fileManager.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: older.path
        )
        try fileManager.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 200)],
            ofItemAtPath: newer.path
        )

        let recordings = RecordingHistoryCatalog(
            directory: directory,
            fileManager: fileManager
        ).recordings()

        XCTAssertEqual(recordings.map(\.url), [newer, older])
        XCTAssertEqual(recordings.first?.fileSize, 2)
    }

    func testCatalogReturnsOnlyExistingRegularFiles() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent(
            "ScreenFree-History-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: directory) }

        try fileManager.createDirectory(
            at: directory.appendingPathComponent("Folder.mov"),
            withIntermediateDirectories: true
        )

        XCTAssertTrue(
            RecordingHistoryCatalog(
                directory: directory,
                fileManager: fileManager
            ).recordings().isEmpty
        )
    }

    func testDeleteRemovesFilesFromDiskAndRefreshesCatalog() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent(
            "ScreenFree-History-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: directory) }

        let first = directory.appendingPathComponent("Recording-a.mp4")
        let second = directory.appendingPathComponent("Recording-b.mp4")
        try Data([0x01]).write(to: first)
        try Data([0x02]).write(to: second)

        let catalog = RecordingHistoryCatalog(
            directory: directory,
            fileManager: fileManager
        )
        let recordings = catalog.recordings()
        XCTAssertEqual(recordings.count, 2)

        let deleted = catalog.delete(
            recordings.filter { $0.url == first }
        )

        XCTAssertEqual(deleted, 1)
        XCTAssertFalse(fileManager.fileExists(atPath: first.path))
        XCTAssertTrue(fileManager.fileExists(atPath: second.path))
        XCTAssertEqual(catalog.recordings().map(\.url), [second])
    }

    func testDeleteRefusesFilesOutsideCatalogDirectory() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent(
            "ScreenFree-History-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: directory) }

        let outsider = fileManager.temporaryDirectory
            .appendingPathComponent("ScreenFree-outsider-\(UUID().uuidString).mp4")
        try Data([0x01]).write(to: outsider)
        defer { try? fileManager.removeItem(at: outsider) }

        let catalog = RecordingHistoryCatalog(
            directory: directory,
            fileManager: fileManager
        )
        let deleted = catalog.delete([
            RecordingHistoryItem(
                url: outsider,
                modifiedAt: Date(),
                fileSize: 1
            )
        ])

        XCTAssertEqual(deleted, 0)
        XCTAssertTrue(fileManager.fileExists(atPath: outsider.path))
    }
}

import Foundation
import ScreenFreeCore

/// The interaction data needed to reconstruct ScreenFree's editable cursor
/// layer when the adjacent project sidecar is unavailable.
struct RecordingInteractionArchive: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int
    var cursorSamples: [CursorSample]
    var clicks: [MouseClick]
    var shortcuts: [ShortcutEvent]

    init(
        version: Int = currentVersion,
        cursorSamples: [CursorSample],
        clicks: [MouseClick],
        shortcuts: [ShortcutEvent]
    ) {
        self.version = version
        self.cursorSamples = cursorSamples
        self.clicks = clicks
        self.shortcuts = shortcuts
    }

    init(project: TimelineProject) {
        self.init(
            cursorSamples: project.cursorSamples,
            clicks: project.clicks,
            shortcuts: project.shortcuts
        )
    }

    var isEmpty: Bool {
        cursorSamples.isEmpty && clicks.isEmpty && shortcuts.isEmpty
    }

    func applying(to project: inout TimelineProject) {
        project.cursorSamples = cursorSamples
        project.clicks = clicks
        project.shortcuts = shortcuts
    }
}

enum RecordingInteractionMetadataError: LocalizedError {
    case unsupportedVersion
    case cannotEncodeArchive
    case exportFailed(String)
    case unsupportedMediaContainer

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion:
            return "This recording contains interaction data from an unsupported ScreenFree version."
        case .cannotEncodeArchive:
            return "ScreenFree could not encode the recorded cursor path."
        case let .exportFailed(details):
            return "ScreenFree could not store the cursor path in the recording: \(details)"
        case .unsupportedMediaContainer:
            return "This media file cannot store ScreenFree cursor data."
        }
    }
}

/// Stores a redundant copy of cursor/click/shortcut data in a standard ISO
/// base-media `uuid` extension box. AVFoundation and ordinary players ignore
/// unknown boxes while ScreenFree can recover the editable interaction layer
/// even if its adjacent `.screenfree` project is moved or lost.
enum RecordingInteractionMetadata {
    private static let boxType = Data("uuid".utf8)
    private static let boxUserType = uuidData(
        UUID(uuidString: "9E5D3161-5BA7-4D3E-9F4F-A7CAED5D71A2")!
    )
    private static let baseHeaderSize: UInt64 = 8
    private static let uuidSize: UInt64 = 16

    static func write(
        _ archive: RecordingInteractionArchive,
        to mediaURL: URL
    ) async throws {
        guard ["mp4", "mov"].contains(
            mediaURL.pathExtension.lowercased()
        ) else {
            throw RecordingInteractionMetadataError
                .unsupportedMediaContainer
        }
        let payload: Data
        do {
            payload = try JSONEncoder().encode(archive)
        } catch {
            throw RecordingInteractionMetadataError.cannotEncodeArchive
        }
        let totalSize = baseHeaderSize + uuidSize + UInt64(payload.count)
        guard totalSize <= UInt64(UInt32.max) else {
            throw RecordingInteractionMetadataError.cannotEncodeArchive
        }
        var box = Data()
        box.append(bigEndianData(UInt32(totalSize)))
        box.append(boxType)
        box.append(boxUserType)
        box.append(payload)

        let handle = try FileHandle(forUpdating: mediaURL)
        let originalLength = try handle.seekToEnd()
        do {
            try handle.write(contentsOf: box)
            try handle.synchronize()
            guard try await read(from: mediaURL) == archive else {
                throw RecordingInteractionMetadataError.exportFailed(
                    "The written interaction box could not be verified."
                )
            }
            try handle.close()
        } catch {
            try? handle.seek(toOffset: originalLength)
            try? handle.truncate(atOffset: originalLength)
            try? handle.close()
            throw error
        }
    }

    static func read(
        from mediaURL: URL
    ) async throws -> RecordingInteractionArchive? {
        let fileSize = try mediaURL.resourceValues(
            forKeys: [.fileSizeKey]
        ).fileSize.map(UInt64.init) ?? 0
        guard fileSize >= baseHeaderSize else { return nil }

        let handle = try FileHandle(forReadingFrom: mediaURL)
        defer { try? handle.close() }
        if let trailing = try readTrailingArchive(
            handle: handle,
            fileSize: fileSize
        ) {
            return trailing
        }
        var offset: UInt64 = 0
        var recovered: RecordingInteractionArchive?
        while offset + baseHeaderSize <= fileSize {
            try handle.seek(toOffset: offset)
            guard let header = try handle.read(upToCount: 8),
                  header.count == 8 else {
                break
            }
            let size32 = header.prefix(4).bigEndianUInt32
            let type = Data(header.suffix(4))
            var headerSize = baseHeaderSize
            let boxSize: UInt64
            if size32 == 1 {
                guard let extended = try handle.read(upToCount: 8),
                      extended.count == 8 else {
                    break
                }
                boxSize = extended.bigEndianUInt64
                headerSize += 8
            } else if size32 == 0 {
                boxSize = fileSize - offset
            } else {
                boxSize = UInt64(size32)
            }
            guard boxSize >= headerSize,
                  offset + boxSize <= fileSize else {
                break
            }
            if type == boxType,
               boxSize >= headerSize + uuidSize,
               let userType = try handle.read(upToCount: Int(uuidSize)),
               userType == boxUserType {
                let payloadSize = boxSize - headerSize - uuidSize
                guard payloadSize <= UInt64(Int.max),
                      let payload = try handle.read(
                        upToCount: Int(payloadSize)
                      ), payload.count == Int(payloadSize) else {
                    break
                }
                recovered = try decodeArchive(payload)
            }
            guard boxSize > 0 else { break }
            offset += boxSize
        }
        return recovered
    }

    /// Our UUID box is always appended, so checking the tail first also works
    /// with unusual source files whose preceding `mdat` box uses size 0 (to
    /// mean "extends to EOF"). The regular top-level walk remains as a
    /// compatibility fallback.
    private static func readTrailingArchive(
        handle: FileHandle,
        fileSize: UInt64
    ) throws -> RecordingInteractionArchive? {
        let maximumTailBytes: UInt64 = 64 * 1_024 * 1_024
        let tailSize = min(fileSize, maximumTailBytes)
        let tailOffset = fileSize - tailSize
        try handle.seek(toOffset: tailOffset)
        guard let tail = try handle.read(upToCount: Int(tailSize)) else {
            return nil
        }
        var marker = boxType
        marker.append(boxUserType)
        guard let markerRange = tail.range(
            of: marker,
            options: .backwards
        ), markerRange.lowerBound >= 4 else {
            return nil
        }
        let sizeRange = (markerRange.lowerBound - 4)..<markerRange.lowerBound
        let boxSize = UInt64(tail[sizeRange].bigEndianUInt32)
        let localBoxStart = markerRange.lowerBound - 4
        guard boxSize >= baseHeaderSize + uuidSize,
              tailOffset + UInt64(localBoxStart) + boxSize == fileSize,
              localBoxStart + Int(boxSize) <= tail.count else {
            return nil
        }
        let payloadRange = markerRange.upperBound..<(localBoxStart + Int(boxSize))
        return try decodeArchive(Data(tail[payloadRange]))
    }

    private static func decodeArchive(
        _ payload: Data
    ) throws -> RecordingInteractionArchive {
        let archive = try JSONDecoder().decode(
            RecordingInteractionArchive.self,
            from: payload
        )
        guard archive.version <= RecordingInteractionArchive.currentVersion else {
            throw RecordingInteractionMetadataError.unsupportedVersion
        }
        return archive
    }

    private static func uuidData(_ value: UUID) -> Data {
        var bytes = value.uuid
        return withUnsafeBytes(of: &bytes) { Data($0) }
    }

    private static func bigEndianData<T: FixedWidthInteger>(
        _ value: T
    ) -> Data {
        var bigEndian = value.bigEndian
        return withUnsafeBytes(of: &bigEndian) { Data($0) }
    }
}

private extension DataProtocol {
    var bigEndianUInt32: UInt32 {
        reduce(UInt32.zero) { ($0 << 8) | UInt32($1) }
    }

    var bigEndianUInt64: UInt64 {
        reduce(UInt64.zero) { ($0 << 8) | UInt64($1) }
    }
}

import AVFoundation
import Foundation

enum OriginalMediaExportError: LocalizedError {
    case missingAudioTrack
    case cannotCreateTrack
    case cannotCreateExportSession
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .missingAudioTrack:
            return "The requested original audio track is unavailable."
        case .cannotCreateTrack:
            return "The original audio track could not be prepared."
        case .cannotCreateExportSession:
            return "The original audio export could not start."
        case .exportFailed:
            return "The original audio track could not be exported."
        }
    }
}

struct OriginalMediaExporter {
    private let delivery = OriginalRecordingDelivery()

    func extractAudio(
        sourceURL: URL,
        trackIndex: Int,
        destinationURL: URL
    ) async throws {
        let sourceAsset = AVURLAsset(url: sourceURL)
        let sourceTracks = try await sourceAsset.loadTracks(
            withMediaType: .audio
        )
        guard sourceTracks.indices.contains(trackIndex) else {
            throw OriginalMediaExportError.missingAudioTrack
        }
        let sourceTrack = sourceTracks[trackIndex]
        let sourceRange = try await sourceTrack.load(.timeRange)
        guard sourceRange.duration > .zero else {
            throw OriginalMediaExportError.missingAudioTrack
        }

        let composition = AVMutableComposition()
        guard let destinationTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw OriginalMediaExportError.cannotCreateTrack
        }
        try destinationTrack.insertTimeRange(
            sourceRange,
            of: sourceTrack,
            at: .zero
        )

        let temporaryURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                ".screenfree-audio-\(UUID().uuidString).m4a"
            )
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw OriginalMediaExportError.cannotCreateExportSession
        }
        session.outputURL = temporaryURL
        session.outputFileType = .m4a
        await session.export()
        guard session.status == .completed else {
            throw session.error ?? OriginalMediaExportError.exportFailed
        }
        try delivery.copy(
            sourceURL: temporaryURL,
            destinationURL: destinationURL
        )
    }
}

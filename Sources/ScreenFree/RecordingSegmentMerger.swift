import AVFoundation
import Foundation

enum RecordingSegmentMergeError: LocalizedError {
    case noSegments
    case cannotCreateTrack
    case cannotCreateExportSession
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .noSegments:
            return "No recording segments were available."
        case .cannotCreateTrack:
            return "The recording segments could not be joined."
        case .cannotCreateExportSession:
            return "The recording merger could not start."
        case .exportFailed:
            return "The recording segments could not be finalized."
        }
    }
}

struct RecordingSegmentMerger {
    func merge(
        _ urls: [URL],
        fileExtension: String
    ) async throws -> URL {
        guard let firstURL = urls.first else {
            throw RecordingSegmentMergeError.noSegments
        }
        guard urls.count > 1 else { return firstURL }

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw RecordingSegmentMergeError.cannotCreateTrack
        }

        var compositionAudioTracks: [AVMutableCompositionTrack] = []
        var insertionTime = CMTime.zero
        var preferredTransform: CGAffineTransform?

        for url in urls {
            let asset = AVURLAsset(url: url)
            guard let videoTrack = try await asset.loadTracks(
                withMediaType: .video
            ).first else {
                continue
            }
            let videoRange = try await videoTrack.load(.timeRange)
            let duration = videoRange.duration
            try compositionVideoTrack.insertTimeRange(
                videoRange,
                of: videoTrack,
                at: insertionTime
            )
            if preferredTransform == nil {
                preferredTransform = try await videoTrack.load(
                    .preferredTransform
                )
            }

            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            while compositionAudioTracks.count < audioTracks.count {
                guard let track = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else {
                    throw RecordingSegmentMergeError.cannotCreateTrack
                }
                compositionAudioTracks.append(track)
            }
            for (index, audioTrack) in audioTracks.enumerated() {
                let audioRange = try await audioTrack.load(.timeRange)
                let availableDuration = CMTimeMinimum(
                    duration,
                    audioRange.duration
                )
                guard availableDuration > .zero else { continue }
                try compositionAudioTracks[index].insertTimeRange(
                    CMTimeRange(
                        start: audioRange.start,
                        duration: availableDuration
                    ),
                    of: audioTrack,
                    at: insertionTime
                )
            }
            insertionTime = insertionTime + duration
        }
        compositionVideoTrack.preferredTransform = preferredTransform ?? .identity

        let outputURL = firstURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Merged-\(UUID().uuidString).\(fileExtension)"
            )
        let outputType: AVFileType = fileExtension.lowercased() == "mov"
            ? .mov
            : .mp4
        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw RecordingSegmentMergeError.cannotCreateExportSession
        }
        session.outputURL = outputURL
        session.outputFileType = outputType
        session.shouldOptimizeForNetworkUse = true
        await session.export()
        guard session.status == .completed else {
            throw session.error ?? RecordingSegmentMergeError.exportFailed
        }
        return outputURL
    }
}
